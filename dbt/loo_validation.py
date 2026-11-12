"""Leave-one-out validation of the BERDO-ComStock nearest-neighbor retrofit estimate.

Real buildings have no observed post-retrofit outcome, but ComStock's simulated offices do.
So each simulated office in turn plays a "real" building: hide it, find its k nearest other
office models with the same distance used for BERDO matching (int_berdo_comstock_matches),
pool their per-fuel upgrade/baseline ratios as in berdo_upgrade_scenarios, apply those to
the held-out model's own baseline fuel use, and compare with what ComStock simulated for it.

This measures how well neighbor transfer works between simulated buildings. It is not a
real-world accuracy: BERDO buildings can differ from every ComStock model in ways the three
matching features don't capture.

Emissions use BERDO's per-fuel factors, which are constant across Boston offices (see the
printout), so the error is in the same units as the BERDO projections.

Run from dbt/ after `dbt build` (read-only):
    uv run python loo_validation.py
Writes analysis_outputs/loo_k_summary.csv, loo_by_upgrade.csv and loo_tests.csv (paired
bootstrap of k = 10 against the baselines).
"""

from __future__ import annotations

import csv
import math
import random
from pathlib import Path

import duckdb

BOOT = 4000  # bootstrap resamples

def main() -> None:
    here = Path(__file__).resolve().parent
    out = here / "analysis_outputs"
    out.mkdir(exist_ok=True)
    con = duckdb.connect(str(here / "ds5500.duckdb"), read_only=True)

    # Use exactly the options offered by the present optimizer, excluding its baseline.
    baseline_ids = con.execute("""
        select distinct upgrade_id from berdo_decision_options
        where lower(trim(upgrade_name)) = 'no upgrade'""").fetchall()
    if len(baseline_ids) != 1:
        raise ValueError("Cannot uniquely identify 'No upgrade' in decision options")
    baseline_id = baseline_ids[0][0]
    upgrades = [int(r[0]) for r in con.execute("""
        select distinct upgrade_id from berdo_decision_options
        where upgrade_id <> ? order by upgrade_id""", [baseline_id]).fetchall()]
    if not upgrades:
        raise ValueError("No eligible upgrade IDs in decision options")

    # Read the office-type crosswalk used by the current matched BERDO cohort.
    office_types = [r[0] for r in con.execute("""
        select distinct cw.comstock_type
        from berdo_comstock_type_crosswalk cw
        join (select distinct property_type from int_berdo_match_buildings) b
            on cw.berdo_type = b.property_type
        order by cw.comstock_type""").fetchall()]
    if not office_types:
        raise ValueError("No ComStock office types in the current BERDO crosswalk")

    # Discover per-fuel columns.
    bcols = {r[0] for r in con.execute("DESCRIBE int_berdo_match_buildings").fetchall()}
    ccols = {r[0] for r in con.execute("DESCRIBE int_comstock_models").fetchall()}
    fuels = sorted(c[:-4] for c in ccols if c.endswith("_kwh") and c in bcols
                   and c[:-4] + "_ghg_kgco2e" in bcols)
    needed = {"electricity", "natural_gas", "oil_propane",
              "district_heating", "district_cooling"}
    if not needed.issubset(fuels):
        raise ValueError(f"Missing fuel fields used by the matching model: {needed - set(fuels)}")

    # Match the neighbor count and compliance year configured by dbt.
    ref_k = con.execute("select max(match_rank) from int_berdo_comstock_matches").fetchone()[0]
    period_rows = con.execute("select distinct period_start from berdo_decision_options").fetchall()
    if ref_k is None or len(period_rows) != 1:
        raise ValueError("Missing reference k or ambiguous decision period")
    ref_k = int(ref_k)
    decision_year = int(period_rows[0][0])
    index_row = con.execute("""
        select electricity_index from int_berdo_electricity_index where year = ?
    """, [decision_year]).fetchone()
    if index_row is None or index_row[0] is None:
        raise ValueError(f"No BERDO electricity index for {decision_year}")
    electricity_index = float(index_row[0])

    # BERDO's per-fuel emission factors (kg CO2e per kWh), median over matched offices.
    ef = {}
    for f in fuels:
        v = con.execute(
            f"select median({f}_ghg_kgco2e / {f}_kwh) from int_berdo_match_buildings where {f}_kwh > 0"
        ).fetchone()[0]
        ef[f] = v
    # No matched office reports district cooling; price it like the fuel_prices seed's proxy,
    # as electricity through a chiller with COP 4.
    if ef["district_cooling"] is None:
        ef["district_cooling"] = ef["electricity"] / 4
    missing_ef = [f for f, value in ef.items() if value is None]
    if missing_ef:
        raise ValueError(f"Cannot estimate emissions factors for: {missing_ef}")
    print("Emission factors (kg/kWh):", {k: round(v, 4) for k, v in ef.items()})

    types = ", ".join("'" + t.replace("'", "''") + "'" for t in office_types)
    # Sweep k = 1 .. floor(sqrt(n)), the usual rule-of-thumb ceiling for k-nearest neighbors.
    n_models = con.execute(
        f"select count(*) from int_comstock_models where upgrade_id = {baseline_id} and comstock_type in ({types})"
    ).fetchone()[0]
    if n_models <= ref_k:
        raise ValueError(f"Need > {ref_k} baseline ComStock models, have {n_models}")
    k_max = math.isqrt(n_models)
    print(f"Office models: {n_models}; k = 1..{k_max}")
    print(f"Upgrades from optimization: {upgrades}; office types: {office_types}")
    print(f"Reference k={ref_k}; decision year={decision_year}; index={electricity_index:.6f}")
    ups = ", ".join(map(str, upgrades))
    cum = ",\n".join(
        f"sum(u.{f}_kwh) over w as cu_{f}, sum(b.{f}_kwh) over w as cb_{f}" for f in fuels
    )
    pred = " + ".join(
        f"h.{f}_kwh * {ef[f]} * coalesce(cu_{f} / nullif(cb_{f}, 0), 1)" for f in fuels
    )
    base = " + ".join(f"h.{f}_kwh * {ef[f]}" for f in fuels)
    actual = " + ".join(f"hu.{f}_kwh * {ef[f]}" for f in fuels)

    fuel_total = " + ".join(f"{f}_kwh" for f in fuels)
    con.execute(f"""
        create temp table loo as
        with m as (
            select *, {fuel_total} as fuel_total_kwh
            from int_comstock_models
            where upgrade_id = {baseline_id} and comstock_type in ({types})
        ),
        -- the BERDO matching distance, with the held-out model h in the BERDO role
        pairs as (
            select h.comstock_id as h_id, c.comstock_id as c_id,
                h.comstock_type = c.comstock_type as same_type,
                abs(ln(h.gfa_sqft / c.gfa_sqft)) + abs(ln(h.eui_kwh_sqft / c.eui_kwh_sqft))
                + 0.5 * (
                    abs(h.electricity_kwh / h.fuel_total_kwh - c.electricity_kwh / c.fuel_total_kwh)
                    + abs(h.natural_gas_kwh / h.fuel_total_kwh - c.natural_gas_kwh / c.fuel_total_kwh)
                    + abs((h.district_heating_kwh + h.district_cooling_kwh) / h.fuel_total_kwh
                        - (c.district_heating_kwh + c.district_cooling_kwh) / c.fuel_total_kwh)
                    + abs(h.oil_propane_kwh / h.fuel_total_kwh - c.oil_propane_kwh / c.fuel_total_kwh)
                ) as distance
            from m as h join m as c on h.comstock_id <> c.comstock_id
        ),
        ranked as (
            select *, row_number() over (partition by h_id order by distance, c_id) as rk
            from pairs
        ),
        -- running sums of neighbor use, so row rk holds the pooled ratio for k = rk
        running as (
            select r.h_id, r.rk, u.upgrade_id, {cum}
            from ranked r
            join int_comstock_models b on b.comstock_id = r.c_id and b.upgrade_id = {baseline_id}
            join int_comstock_models u on u.comstock_id = r.c_id and u.upgrade_id in ({ups})
            window w as (partition by r.h_id, u.upgrade_id order by r.rk)
        ),
        n as (select count(*) - 1 as n_others from m)
        select r.h_id, h.comstock_type, h.gfa_sqft,
            case when r.rk = n.n_others then 'all' else r.rk::varchar end as k,
            r.upgrade_id,
            ({base}) as base_ghg, ({actual}) as actual_ghg, ({pred}) as pred_ghg,
            h.electricity_kwh * {ef["electricity"]} as base_elec_ghg,
            hu.electricity_kwh * {ef["electricity"]} as actual_elec_ghg,
            h.electricity_kwh * {ef["electricity"]}
                * coalesce(cu_electricity / nullif(cb_electricity, 0), 1)
                as pred_elec_ghg
        from running r
        cross join n
        join m h on h.comstock_id = r.h_id
        join int_comstock_models hu on hu.comstock_id = r.h_id and hu.upgrade_id = r.upgrade_id
        where r.rk <= {k_max} or r.rk = n.n_others
    """)

    # Same-type baseline: pool every other model of the held-out model's ComStock type, i.e.
    # what you'd predict knowing only small / medium / large office.
    sums = ",\n".join(f"sum(u.{f}_kwh) as su_{f}, sum(b.{f}_kwh) as sb_{f}" for f in fuels)
    type_pred = " + ".join(
        f"h.{f}_kwh * {ef[f]} * coalesce((t.su_{f} - hu.{f}_kwh) / nullif(t.sb_{f} - h.{f}_kwh, 0), 1)"
        for f in fuels
    )
    con.execute(f"""
        insert into loo
        with t as (
            select b.comstock_type, u.upgrade_id, {sums}
            from int_comstock_models b
            join int_comstock_models u on u.comstock_id = b.comstock_id and u.upgrade_id in ({ups})
            where b.upgrade_id = {baseline_id} and b.comstock_type in ({types})
            group by all
        )
        select h.comstock_id, h.comstock_type, h.gfa_sqft, 'type', t.upgrade_id,
            ({base}), ({actual}), ({type_pred}),
        h.electricity_kwh * {ef["electricity"]},
        hu.electricity_kwh * {ef["electricity"]},
        h.electricity_kwh * {ef["electricity"]} * coalesce(
            (t.su_electricity - hu.electricity_kwh)
            / nullif(t.sb_electricity - h.electricity_kwh, 0), 1)
        from int_comstock_models h
        join t on t.comstock_type = h.comstock_type
        join int_comstock_models hu on hu.comstock_id = h.comstock_id and hu.upgrade_id = t.upgrade_id
        where h.upgrade_id = {baseline_id} and h.comstock_type in ({types})
    """)

    # Errors: emissions reduction in percentage points, and post-retrofit intensity.
    errors = """
        select *,
            100 * abs((actual_ghg - pred_ghg) / base_ghg) as err_pp,
            abs(actual_ghg - pred_ghg) / gfa_sqft as err_kg_sqft,
            100 * (1 - actual_ghg / base_ghg) as actual_reduction_pct
        from loo where base_ghg > 0
    """
    con.execute(f"""
        copy (
            select k, count(distinct h_id) as held_out_models, count(*) as predictions,
                round(avg(err_pp), 2) as mae_pp,
                round(median(err_pp), 2) as median_ae_pp,
                round(quantile_cont(err_pp, 0.9), 2) as p90_ae_pp,
                round(avg(err_kg_sqft), 3) as mae_kg_sqft
            from ({errors})
            group by k
            order by try_cast(k as int) nulls last, k
        ) to '{out / "loo_k_summary.csv"}' (header)
    """)
    con.execute(f"""
        copy (
            select k, upgrade_id,
                round(avg(actual_reduction_pct), 1) as mean_actual_reduction_pct,
                round(avg(err_pp), 2) as mae_pp
            from ({errors})
            where k in ('1', '{ref_k}', 'type', 'all')
            group by all order by upgrade_id, k
        ) to '{out / "loo_by_upgrade.csv"}' (header)
    """)
    print(open(out / "loo_k_summary.csv").read())
    print(open(out / "loo_by_upgrade.csv").read())

    # Monte Carlo needs signed *2030-period-adjusted* errors (positive = optimistic model).
    # Keep original LOO summary metrics above unchanged (2025-equivalent errors).
    # Apply BERDO's decision-year electricity index to both prediction and actual.
    con.execute(f"""
        copy (
            select h_id as held_out_model_id,
                comstock_type, upgrade_id, gfa_sqft, {decision_year} as decision_year,
                (base_ghg - base_elec_ghg * (1 - {electricity_index})) / gfa_sqft
                    as baseline_intensity_kgco2e_sqft,
                (pred_ghg - pred_elec_ghg * (1 - {electricity_index})) / gfa_sqft
                    as predicted_intensity_kgco2e_sqft,
                (actual_ghg - actual_elec_ghg * (1 - {electricity_index})) / gfa_sqft
                    as actual_intensity_kgco2e_sqft,
                ((actual_ghg - actual_elec_ghg * (1 - {electricity_index}))
                 - (pred_ghg - pred_elec_ghg * (1 - {electricity_index}))) / gfa_sqft
                    as signed_error_kgco2e_sqft,
                100 * ((actual_ghg - actual_elec_ghg * (1 - {electricity_index}))
                    - (pred_ghg - pred_elec_ghg * (1 - {electricity_index})))
                    / nullif(base_ghg - base_elec_ghg * (1 - {electricity_index}), 0)
                    as signed_error_pp
            from ({errors})
            where k = '{ref_k}' and gfa_sqft > 0
            order by h_id, upgrade_id
        ) to '{out / "loo_residuals.csv"}' (header)
    """)
    print('Saved signed residuals to', out / 'loo_residuals.csv')

    # Make incomplete upgrade coverage visible instead of silently inventing errors.
    observed_upgrades = {r[0] for r in con.execute(f"""
        select distinct upgrade_id from loo where k = '{ref_k}'""").fetchall()}
    unvalidated = sorted(set(upgrades) - observed_upgrades)
    if unvalidated:
        print('WARNING: No LOO residuals for eligible upgrades:', unvalidated)

    # Is configured k better than the baselines? Paired bootstrap over held-out models: each
    # model's mean error across the eight upgrades, resampled with replacement.
    per_model = con.execute(f"""
        select h_id, k, avg(err_pp) as e from ({errors})
        where k in ('1', '{ref_k}', 'type', 'all') group by all
    """).fetchall()
    by: dict[str, dict[int, float]] = {}
    for h, k, e in per_model:
        by.setdefault(k, {})[h] = e
    ids = sorted(by[str(ref_k)])
    rng = random.Random(5500)
    rows = []
    for other in ("all", "type", "1"):
        if other == str(ref_k):
            continue
        common_ids = sorted(set(ids) & set(by.get(other, {})))
        if not common_ids:
            print(f"WARNING: No paired observations for reference k vs {other}")
            continue
        diffs = [by[str(ref_k)][h] - by[other][h] for h in common_ids]
        point = sum(diffs) / len(diffs)
        boots = sorted(
            sum(diffs[rng.randrange(len(diffs))] for _ in diffs) / len(diffs) for _ in range(BOOT)
        )
        lo, hi = boots[int(0.025 * BOOT)], boots[int(0.975 * BOOT) - 1]
        rows.append({
            "comparison": f"{ref_k} minus {other}",
            "mean_diff_pp": round(point, 2),
            "ci95_low_pp": round(lo, 2),
            "ci95_high_pp": round(hi, 2),
            "share_models_reference_better": round(sum(d < 0 for d in diffs) / len(diffs), 3),
        })
    with (out / "loo_tests.csv").open("w", newline="") as fh:
        fieldnames = ["comparison", "mean_diff_pp", "ci95_low_pp", "ci95_high_pp",
                      "share_models_reference_better"]
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(open(out / "loo_tests.csv").read())


if __name__ == "__main__":
    main()