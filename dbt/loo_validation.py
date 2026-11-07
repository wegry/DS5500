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
OFFICE_TYPES = ("SmallOffice", "MediumOffice", "LargeOffice")  # crosswalk for BERDO "Office"
UPGRADES = (43, 48, 49, 52, 54, 55, 56, 57)  # the measures and packages in the decision
FUELS = ("electricity", "natural_gas", "oil_propane", "district_heating", "district_cooling")


def main() -> None:
    here = Path(__file__).resolve().parent
    out = here / "analysis_outputs"
    con = duckdb.connect(str(here / "ds5500.duckdb"), read_only=True)

    # BERDO's per-fuel emission factors (kg CO2e per kWh), median over matched offices.
    ef = {}
    for f in FUELS:
        v = con.execute(
            f"select median({f}_ghg_kgco2e / {f}_kwh) from int_berdo_match_buildings where {f}_kwh > 0"
        ).fetchone()[0]
        ef[f] = v
    # No matched office reports district cooling; price it like the fuel_prices seed's proxy,
    # as electricity through a chiller with COP 4.
    if ef["district_cooling"] is None:
        ef["district_cooling"] = ef["electricity"] / 4
    print("Emission factors (kg/kWh):", {k: round(v, 4) for k, v in ef.items()})

    types = ", ".join(f"'{t}'" for t in OFFICE_TYPES)
    # Sweep k = 1 .. floor(sqrt(n)), the usual rule-of-thumb ceiling for k-nearest neighbors.
    n_models = con.execute(
        f"select count(*) from int_comstock_models where upgrade_id = 0 and comstock_type in ({types})"
    ).fetchone()[0]
    k_max = math.isqrt(n_models)
    print(f"Office models: {n_models}; k = 1..{k_max}")
    ups = ", ".join(map(str, UPGRADES))
    cum = ",\n".join(
        f"sum(u.{f}_kwh) over w as cu_{f}, sum(b.{f}_kwh) over w as cb_{f}" for f in FUELS
    )
    pred = " + ".join(
        f"h.{f}_kwh * {ef[f]} * coalesce(cu_{f} / nullif(cb_{f}, 0), 1)" for f in FUELS
    )
    base = " + ".join(f"h.{f}_kwh * {ef[f]}" for f in FUELS)
    actual = " + ".join(f"hu.{f}_kwh * {ef[f]}" for f in FUELS)

    con.execute(f"""
        create temp table loo as
        with m as (
            select *,
                electricity_kwh + natural_gas_kwh + district_heating_kwh
                    + district_cooling_kwh + oil_propane_kwh as fuel_total_kwh
            from int_comstock_models
            where upgrade_id = 0 and comstock_type in ({types})
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
            join int_comstock_models b on b.comstock_id = r.c_id and b.upgrade_id = 0
            join int_comstock_models u on u.comstock_id = r.c_id and u.upgrade_id in ({ups})
            window w as (partition by r.h_id, u.upgrade_id order by r.rk)
        ),
        n as (select count(*) - 1 as n_others from m)
        select r.h_id, h.comstock_type, h.gfa_sqft,
            case when r.rk = n.n_others then 'all' else r.rk::varchar end as k,
            r.upgrade_id,
            ({base}) as base_ghg, ({actual}) as actual_ghg, ({pred}) as pred_ghg
        from running r
        cross join n
        join m h on h.comstock_id = r.h_id
        join int_comstock_models hu on hu.comstock_id = r.h_id and hu.upgrade_id = r.upgrade_id
        where r.rk <= {k_max} or r.rk = n.n_others
    """)

    # Same-type baseline: pool every other model of the held-out model's ComStock type, i.e.
    # what you'd predict knowing only small / medium / large office.
    sums = ",\n".join(f"sum(u.{f}_kwh) as su_{f}, sum(b.{f}_kwh) as sb_{f}" for f in FUELS)
    type_pred = " + ".join(
        f"h.{f}_kwh * {ef[f]} * coalesce((t.su_{f} - hu.{f}_kwh) / nullif(t.sb_{f} - h.{f}_kwh, 0), 1)"
        for f in FUELS
    )
    con.execute(f"""
        insert into loo
        with t as (
            select b.comstock_type, u.upgrade_id, {sums}
            from int_comstock_models b
            join int_comstock_models u on u.comstock_id = b.comstock_id and u.upgrade_id in ({ups})
            where b.upgrade_id = 0 and b.comstock_type in ({types})
            group by all
        )
        select h.comstock_id, h.comstock_type, h.gfa_sqft, 'type', t.upgrade_id,
            ({base}), ({actual}), ({type_pred})
        from int_comstock_models h
        join t on t.comstock_type = h.comstock_type
        join int_comstock_models hu on hu.comstock_id = h.comstock_id and hu.upgrade_id = t.upgrade_id
        where h.upgrade_id = 0 and h.comstock_type in ({types})
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
            where k in ('1', '10', 'type', 'all')
            group by all order by upgrade_id, k
        ) to '{out / "loo_by_upgrade.csv"}' (header)
    """)
    print(open(out / "loo_k_summary.csv").read())
    print(open(out / "loo_by_upgrade.csv").read())

    # Is k = 10 really better than the baselines? Paired bootstrap over held-out models: each
    # model's mean error across the eight upgrades, resampled with replacement.
    per_model = con.execute(f"""
        select h_id, k, avg(err_pp) as e from ({errors})
        where k in ('1', '10', 'type', 'all') group by all
    """).fetchall()
    by: dict[str, dict[int, float]] = {}
    for h, k, e in per_model:
        by.setdefault(k, {})[h] = e
    ids = sorted(by["10"])
    rng = random.Random(5500)
    rows = []
    for other in ("all", "type", "1"):
        diffs = [by["10"][h] - by[other][h] for h in ids]
        point = sum(diffs) / len(diffs)
        boots = sorted(
            sum(diffs[rng.randrange(len(diffs))] for _ in diffs) / len(diffs) for _ in range(BOOT)
        )
        lo, hi = boots[int(0.025 * BOOT)], boots[int(0.975 * BOOT) - 1]
        rows.append({
            "comparison": f"k=10 minus {other}",
            "mean_diff_pp": round(point, 2),
            "ci95_low_pp": round(lo, 2),
            "ci95_high_pp": round(hi, 2),
            "share_models_k10_better": round(sum(d < 0 for d in diffs) / len(diffs), 3),
        })
    with (out / "loo_tests.csv").open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(open(out / "loo_tests.csv").read())


if __name__ == "__main__":
    main()
