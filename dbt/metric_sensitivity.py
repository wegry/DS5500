"""Compare BERDO-ComStock matching distance metrics.

Each metric is a weighting of int_berdo_comstock_matches' three terms (log size gap, log EUI
gap, fuel-share gap), optionally with the district rule: a candidate model must agree with
the building on using any district energy at all. The same choices are dbt vars
(match_w_size, match_w_eui, match_w_fuel, match_district_rule), so a metric that wins here
can be built with, e.g.
    uv run dbt build --profiles-dir . --vars '{match_district_rule: true}'

Two read-only checks at the configured k:
1. Leave-one-out accuracy, as in the analysis_loo_* dbt models: hide each ComStock office model, predict
   its upgrade emissions from its k nearest others under the metric, compare with what
   ComStock simulated. Reported overall and for district-energy models, with a paired
   bootstrap of each metric against the original (pre-district-rule) one.
2. How much the BERDO matches move: overlap of each building's k neighbors with the original
   metric's, and how many neighbors of district-energy buildings use district energy.

With --decisions, also:
3. What the optimizer recommends: rebuild everything downstream of the matches once per
   metric (not the staging tables) and compare five-year decisions for offices over the 2030
   limit with the original metric's. The project's default metric is rebuilt at the end, even on error.

Run from dbt/ after `dbt build`:
    uv run python metric_sensitivity.py [--decisions]
Writes analysis_outputs/metric_sensitivity/{loo_summary,loo_tests,berdo_overlap}.csv, and
with --decisions {decisions,decision_summary}.csv.
"""

from __future__ import annotations

import csv
import random
import subprocess
import sys
from pathlib import Path

import duckdb

BOOT = 4000
HERE = Path(__file__).resolve().parent
OUT = HERE / "analysis_outputs" / "metric_sensitivity"
FUELS = ["electricity", "natural_gas", "oil_propane", "district_heating", "district_cooling"]

con = duckdb.connect(str(HERE / "ds5500.duckdb"), read_only=True)


def one(sql, params=None):
    return con.execute(sql, params or []).fetchone()


def gap_sql(a, b, a_shares):
    """The three distance terms between building/model `a` and model `b`. `a_shares` says
    whether `a` carries precomputed *_share columns (BERDO) or raw kWh (ComStock)."""
    def share(x, expr, has_shares, col):
        return f"{x}.{col}_share" if has_shares else f"({expr}) / {x}.fuel_total_kwh"

    def a_share(col, expr):
        return share(a, expr, a_shares, col)

    def b_share(expr):
        return f"({expr}) / {b}.fuel_total_kwh"

    terms = [
        ("electricity", "{x}.electricity_kwh"),
        ("natural_gas", "{x}.natural_gas_kwh"),
        ("district", "{x}.district_heating_kwh + {x}.district_cooling_kwh"),
        ("oil_propane", "{x}.oil_propane_kwh"),
    ]
    fuel = " + ".join(
        f"abs({a_share(col, e.format(x=a))} - {b_share(e.format(x=b))})" for col, e in terms
    )
    return (
        f"abs(ln({a}.gfa_sqft / {b}.gfa_sqft)) as size_gap, "
        f"abs(ln({a}.eui_kwh_sqft / {b}.eui_kwh_sqft)) as eui_gap, "
        f"0.5 * ({fuel}) as fuel_gap"
    )


def main() -> dict:
    OUT.mkdir(parents=True, exist_ok=True)

    k = int(one("select max(match_rank) from int_berdo_comstock_matches")[0])
    upgrades = [r[0] for r in con.execute("""
        select distinct upgrade_id from berdo_decision_options
        where lower(trim(upgrade_name)) <> 'no upgrade' order by 1""").fetchall()]
    ups = ", ".join(map(str, upgrades))
    types = ", ".join(f"'{r[0]}'" for r in con.execute("""
        select distinct cw.comstock_type from berdo_comstock_type_crosswalk cw
        join (select distinct property_type from int_berdo_match_buildings) b
          on cw.berdo_type = b.property_type order by 1""").fetchall())

    # BERDO's per-fuel emission factors, as in analysis_loo_predictions
    ef = {}
    for f in FUELS:
        ef[f] = one(f"""select median({f}_ghg_kgco2e / {f}_kwh)
                        from int_berdo_match_buildings where {f}_kwh > 0""")[0]
    if ef["district_cooling"] is None:
        ef["district_cooling"] = ef["electricity"] / 4

    con.execute(f"""
        create temp table m as
        select *, {' + '.join(f'{f}_kwh' for f in FUELS)} as fuel_total_kwh,
            district_heating_kwh + district_cooling_kwh > 0 as uses_district
        from int_comstock_models where upgrade_id = 0 and comstock_type in ({types})
    """)
    # every BERDO-candidate pair, as int_berdo_comstock_matches builds them
    con.execute(f"""
        create temp table berdo_pairs as
        select b.berdo_id, c.comstock_id, b.district_share > 0 as b_district,
            c.uses_district as c_district, {gap_sql('b', 'c', True)}
        from int_berdo_match_buildings b
        join berdo_comstock_type_crosswalk cw on b.property_type = cw.berdo_type
        join m c on c.comstock_type = cw.comstock_type
    """)
    # every held-out/other pair among ComStock office models (LOO)
    con.execute(f"""
        create temp table loo_pairs as
        select h.comstock_id as h_id, c.comstock_id as c_id, h.uses_district as b_district,
            c.uses_district as c_district, {gap_sql('h', 'c', False)}
        from m h join m c on h.comstock_id <> c.comstock_id
    """)

    # "standardized": each term divided by its spread over the BERDO candidate pairs, so no
    # term dominates by scale; rescaled so the weights sum to 3 like the original metric
    sd = one("select stddev(size_gap), stddev(eui_gap), stddev(fuel_gap) from berdo_pairs")
    inv = [1 / s for s in sd]
    std_w = tuple(round(3 * w / sum(inv), 3) for w in inv)
    print(f"k={k}; term SDs over BERDO pairs (size, EUI, fuel): {[round(s, 3) for s in sd]}")
    print(f"standardized weights: {std_w}")

    metrics = {
        "original": ((1, 1, 1), False),
        "standardized": (std_w, False),
        "fuel x3": ((1, 1, 3), False),
        "district rule": ((1, 1, 1), True),
        "standardized + district rule": (std_w, True),
    }

    def ranked(pairs, a_col, b_col, w, rule):
        dist = f"{w[0]} * size_gap + {w[1]} * eui_gap + {w[2]} * fuel_gap"
        where = "where b_district = c_district" if rule else ""
        return f"""
            select {a_col} as a, {b_col} as c, b_district, c_district from {pairs} {where}
            qualify row_number() over (partition by {a_col} order by {dist}, {b_col}) <= {k}
        """

    # ---- 1. leave-one-out accuracy ----------------------------------------------------
    pooled = ", ".join(
        f"coalesce(sum(u.{f}_kwh) / nullif(sum(b.{f}_kwh), 0), 1) as r_{f}" for f in FUELS
    )
    pred = " + ".join(f"h.{f}_kwh * {ef[f]} * p.r_{f}" for f in FUELS)
    base = " + ".join(f"h.{f}_kwh * {ef[f]}" for f in FUELS)
    actual = " + ".join(f"hu.{f}_kwh * {ef[f]}" for f in FUELS)
    con.execute("create temp table loo (metric varchar, h_id bigint, district boolean, "
                "upgrade_id bigint, err_pp double)")
    for name, (w, rule) in metrics.items():
        con.execute(f"""
            insert into loo
            with nb as ({ranked('loo_pairs', 'h_id', 'c_id', w, rule)}),
            p as (
                select nb.a as h_id, u.upgrade_id, {pooled}
                from nb
                join int_comstock_models b on b.comstock_id = nb.c and b.upgrade_id = 0
                join int_comstock_models u on u.comstock_id = nb.c and u.upgrade_id in ({ups})
                group by all
            )
            select '{name}', h.comstock_id, h.uses_district, p.upgrade_id,
                100 * abs((({actual}) - ({pred})) / ({base}))
            from p
            join m h on h.comstock_id = p.h_id
            join int_comstock_models hu
              on hu.comstock_id = p.h_id and hu.upgrade_id = p.upgrade_id
            where ({base}) > 0
        """)

    order = "case metric " + " ".join(
        f"when '{n}' then {i}" for i, n in enumerate(metrics)) + " end"
    con.execute(f"""
        copy (
            select metric,
                round(avg(err_pp), 2) as mae_pp,
                round(quantile_cont(err_pp, 0.9), 2) as p90_ae_pp,
                round(avg(err_pp) filter (where district), 2) as mae_pp_district_models,
                round(avg(err_pp) filter (where not district), 2) as mae_pp_other_models,
                count(distinct h_id) filter (where district) as district_models,
                count(distinct h_id) as models
            from loo group by metric order by {order}
        ) to '{OUT / "loo_summary.csv"}' (header)
    """)

    # paired bootstrap over held-out models: each model's mean error across upgrades
    per_model: dict[str, dict[int, tuple[bool, float]]] = {}
    for metric, h, d, e in con.execute(
        "select metric, h_id, district, avg(err_pp) from loo group by all"
    ).fetchall():
        per_model.setdefault(metric, {})[h] = (d, e)
    rng = random.Random(5500)
    rows = []
    for name in list(metrics)[1:]:
        for subset in ("all", "district"):
            ids = sorted(h for h, (d, _) in per_model["original"].items()
                         if (subset == "all" or d) and h in per_model[name])
            diffs = [per_model[name][h][1] - per_model["original"][h][1] for h in ids]
            boots = sorted(sum(diffs[rng.randrange(len(diffs))] for _ in diffs) / len(diffs)
                           for _ in range(BOOT))
            rows.append({
                "metric": name, "models": subset, "n": len(diffs),
                "mean_diff_vs_original_pp": round(sum(diffs) / len(diffs), 2),
                "ci95_low_pp": round(boots[int(0.025 * BOOT)], 2),
                "ci95_high_pp": round(boots[int(0.975 * BOOT) - 1], 2),
            })
    with (OUT / "loo_tests.csv").open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    # ---- 2. how far the BERDO matches move ----------------------------------------------
    con.execute("create temp table nbrs (metric varchar, berdo_id bigint, comstock_id bigint, "
                "b_district boolean, c_district boolean)")
    for name, (w, rule) in metrics.items():
        con.execute(f"insert into nbrs select '{name}', * from "
                    f"({ranked('berdo_pairs', 'berdo_id', 'comstock_id', w, rule)})")
    con.execute(f"""
        copy (
            with shared as (
                select x.metric, x.berdo_id, any_value(x.b_district) as b_district,
                    count(c.comstock_id) as shared
                from nbrs x
                left join nbrs c on c.metric = 'original' and c.berdo_id = x.berdo_id
                    and c.comstock_id = x.comstock_id
                group by all
            ),
            dist as (
                select metric, avg(c_district::int) as share_district_nbrs
                from nbrs where b_district group by metric
            )
            select metric,
                round(avg(shared / (2 * {k} - shared)), 3) as mean_jaccard_vs_original,
                count(*) filter (where shared < {k}) as buildings_with_new_neighbors,
                count(*) filter (where shared <= {k} / 2) as buildings_half_replaced,
                round(avg(shared / (2 * {k} - shared)) filter (where b_district), 3)
                    as mean_jaccard_district_buildings,
                round(any_value(d.share_district_nbrs), 3)
                    as district_buildings_share_district_nbrs
            from shared join dist d using (metric)
            group by metric order by {order}
        ) to '{OUT / "berdo_overlap.csv"}' (header)
    """)

    for f in ("loo_summary.csv", "loo_tests.csv", "berdo_overlap.csv"):
        print(f"\n{f}\n" + (OUT / f).read_text())
    return metrics


# ---- 3. what the optimizer recommends under each metric (rebuilds the warehouse) ----------
def build(w, rule, log):
    """Rebuild from the matches down with metric (w, rule); w=None uses dbt_project.yml's."""
    cmd = ["uv", "run", "dbt", "build", "--profiles-dir", ".", "-s", "int_berdo_comstock_matches+"]
    vars_ = "project defaults"
    if w is not None:
        vars_ = (f"{{match_w_size: {w[0]}, match_w_eui: {w[1]}, match_w_fuel: {w[2]}, "
                 f"match_district_rule: {str(rule).lower()}}}")
        cmd += ["--vars", vars_]
    p = subprocess.run(cmd, cwd=HERE, stdout=log, stderr=subprocess.STDOUT, check=False)
    if p.returncode:
        raise RuntimeError(f"dbt build failed for {vars_}; see {log.name}")


def decisions(metrics) -> None:
    """Rebuild everything downstream of the matches once per metric, keep the five-year
    decisions for offices over the 2030 limit, then restore the default metric."""
    cols = ["berdo_id", "district", "recommended_upgrade_id", "meets_standard",
            "has_compliant_option", "total_cost_mid_usd", "mean_option_reduction_pct"]
    rows = []
    with (OUT / "decision_builds.log").open("w") as log:
        try:
            for name, (w, rule) in metrics.items():
                print(f"building {name} ...", flush=True)
                build(w, rule, log)
                db = duckdb.connect(str(HERE / "ds5500.duckdb"), read_only=True)
                try:
                    for r in db.execute("""
                        select d.berdo_id, b.district_share > 0,
                            d.recommended_upgrade_id, d.meets_standard,
                            coalesce(bool_or(o.meets_standard), false),
                            d.total_cost_mid_usd,
                            -- predicted cut across the offered retrofits, vs no upgrade
                            100 * avg(1 - o.projected_ghg_intensity_kgco2e_sqft
                                / d.baseline_ghg_intensity_kgco2e_sqft)
                                filter (where o.upgrade_id <> 0)
                        from berdo_decisions d
                        join int_berdo_match_buildings b using (berdo_id)
                        left join berdo_decision_options o using (berdo_id)
                        where not d.meets_standard_without_upgrade
                        group by all order by 1
                    """).fetchall():
                        rows.append({"metric": name, **dict(zip(cols, r))})
                finally:
                    db.close()
        finally:
            print("restoring the project's default metric ...", flush=True)
            build(None, None, log)

    with (OUT / "decisions.csv").open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["metric", *cols])
        w.writeheader()
        w.writerows(rows)

    ref = {r["berdo_id"]: r for r in rows if r["metric"] == "original"}
    summary = []
    for name in metrics:
        cur = [r for r in rows if r["metric"] == name]
        if {r["berdo_id"] for r in cur} != set(ref):
            raise AssertionError(f"{name}: the over-limit cohort changed")
        for subset in ("all", "district"):
            s = [r for r in cur if subset == "all" or r["district"]]
            summary.append({
                "metric": name, "offices": subset, "n": len(s),
                "has_compliant_option": sum(r["has_compliant_option"] for r in s),
                "choose_retrofit": sum(r["recommended_upgrade_id"] != 0 for r in s),
                "choice_meets_standard": sum(bool(r["meets_standard"]) for r in s),
                "different_choice_vs_original": sum(
                    r["recommended_upgrade_id"] != ref[r["berdo_id"]]["recommended_upgrade_id"]
                    for r in s),
                "different_compliance_vs_original": sum(
                    r["meets_standard"] != ref[r["berdo_id"]]["meets_standard"] for r in s),
                "mean_option_reduction_pct": round(
                    sum(r["mean_option_reduction_pct"] or 0 for r in s) / len(s), 1),
                "total_5yr_cost_musd": round(sum(r["total_cost_mid_usd"] for r in s) / 1e6, 2),
            })
    with (OUT / "decision_summary.csv").open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(summary[0]))
        w.writeheader()
        w.writerows(summary)
    print("\ndecision_summary.csv\n" + (OUT / "decision_summary.csv").read_text())


if __name__ == "__main__":
    metrics = main()
    con.close()  # dbt needs the write lock
    if "--decisions" in sys.argv:
        decisions(metrics)
