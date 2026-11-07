"""Export the numbers Presentation 2 plots from the dbt DuckDB warehouse.

Run from the repo root after `dbt build`:
    uv run python presentation-2/make_data.py
"""

import json
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "presentation-2" / "data"
CASE_ID = 106476  # 24-32 Farnsworth St, Fort Point

con = duckdb.connect(str(ROOT / "dbt" / "ds5500.duckdb"), read_only=True)


def rows(sql):
    cur = con.execute(sql)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def write_csv(name, sql):
    con.execute(f"copy ({sql}) to '{OUT / name}' (header, delimiter ',')")


OVER = "berdo_id in (select berdo_id from berdo_decisions where not meets_standard_without_upgrade)"

# Outcome of the cheapest option for the 99 over-limit buildings, by horizon and payer
write_csv(
    "outcomes.csv",
    f"""
    select '5 yr, owner' as scenario, 1 as ord,
        count(*) filter (where recommended_upgrade_id = 0) as acp_only,
        count(*) filter (where recommended_upgrade_id <> 0 and not meets_standard) as retrofit_over,
        count(*) filter (where recommended_upgrade_id <> 0 and meets_standard) as retrofit_compliant
    from berdo_decisions where {OVER}
    union all
    select case perspective when 'financial' then '20 yr, owner' else '20 yr, society' end,
        case perspective when 'financial' then 2 else 3 end,
        count(*) filter (where upgrade_id = 0),
        count(*) filter (where upgrade_id <> 0 and not meets_standard_at_start),
        count(*) filter (where upgrade_id <> 0 and meets_standard_at_start)
    from berdo_global_cost
    where cost_rank_mid = 1 and energy_price = 'mid' and scenario = 'frozen' and {OVER}
    group by perspective
    order by ord
    """,
)

# Case study: cost of each option relative to ACP-only, three ways
write_csv(
    "case_study.csv",
    f"""
    with five as (
        select upgrade_id, total_cost_mid_usd as cost from berdo_decision_options
        where berdo_id = {CASE_ID}
    ), twenty as (
        select upgrade_id, perspective, global_cost_mid_usd as cost from berdo_global_cost
        where berdo_id = {CASE_ID} and energy_price = 'mid' and scenario = 'frozen'
    ), opts as (
        select upgrade_id, upgrade_name, projected_ghg_intensity_kgco2e_sqft as intensity,
            meets_standard, installed_cost_mid_usd
        from berdo_decision_options where berdo_id = {CASE_ID}
    )
    select o.upgrade_id, o.upgrade_name, o.intensity, o.meets_standard, o.installed_cost_mid_usd,
        f.cost - (select cost from five where upgrade_id = 0) as delta_5yr_owner,
        tf.cost - (select cost from twenty where upgrade_id = 0 and perspective = 'financial') as delta_20yr_owner,
        ts.cost - (select cost from twenty where upgrade_id = 0 and perspective = 'societal') as delta_20yr_society
    from opts o
    join five f using (upgrade_id)
    join twenty tf on tf.upgrade_id = o.upgrade_id and tf.perspective = 'financial'
    join twenty ts on ts.upgrade_id = o.upgrade_id and ts.perspective = 'societal'
    order by o.upgrade_id
    """,
)

# Break-even ACP: the lowest $/tCO2e at which an option that meets the 2030 standard is the
# owner's cheapest 20-year choice. Owner-side emissions cost scales linearly with the ACP
# rate, so each option's cost is a line in the rate and the break-even is an LP over pairs.
acp = 234
write_csv(
    "breakeven.csv",
    f"""
    with g as (
        select berdo_id, upgrade_id, meets_standard_at_start as ok,
            capital_pv_mid_usd + energy_pv_usd + om_pv_mid_usd as fixed,
            emissions_cost_pv_usd / {acp} as em  -- PV per $1/t of ACP
        from berdo_global_cost
        where perspective = 'financial' and energy_price = 'mid' and scenario = 'frozen' and {OVER}
    ), bounds as (
        select a.berdo_id, a.upgrade_id,
            greatest(0, coalesce(max(case when b.em > a.em then (a.fixed - b.fixed) / (b.em - a.em) end), 0)) as lo,
            coalesce(min(case when b.em < a.em then (b.fixed - a.fixed) / (a.em - b.em) end), 1e12) as hi,
            bool_and(b.em <> a.em or a.fixed <= b.fixed) as tie_ok
        from g a join g b on a.berdo_id = b.berdo_id and a.upgrade_id <> b.upgrade_id
        where a.ok
        group by a.berdo_id, a.upgrade_id
    )
    select berdo_id, round(min(lo), 1) as breakeven_acp_usd_per_t
    from bounds where lo <= hi and tie_ok
    group by berdo_id order by 2
    """,
)

# 20-year outcomes under each energy scenario (dbt/seeds/energy_scenarios.csv, in seed order)
# for the 99 offices over the 2030 limit at today's emissions factors: those already under it
# in 2030 with no retrofit once BERDO's factor falls, and for the rest, whether the cheapest
# option is paying, a retrofit still over the limit, or a compliant one. Plus Farnsworth's pick.
scen_order = [r["scenario"] for r in rows(f"select scenario from read_csv('{ROOT / 'dbt' / 'seeds' / 'energy_scenarios.csv'}')")]
order_case = " ".join(f"when '{sc}' then {i}" for i, sc in enumerate(scen_order))
write_csv(
    "scenarios.csv",
    f"""
    with g as (
        select * from berdo_global_cost
        where energy_price = 'mid' and {OVER}
    ), already as (
        -- under the 2030 limit with no retrofit, as BERDO counts emissions in this scenario
        select scenario, berdo_id from g
        where upgrade_id = 0 and perspective = 'financial' and meets_standard_at_start
    )
    select g.scenario, any_value(s.label) as label, case g.scenario {order_case} end as ord,
        g.perspective,
        count(*) filter (where a.berdo_id is not null) as under_limit_anyway,
        count(*) filter (where a.berdo_id is null and g.upgrade_id = 0) as acp_only,
        count(*) filter (where a.berdo_id is null and g.upgrade_id <> 0 and not g.meets_standard_at_start)
            as retrofit_over,
        count(*) filter (where a.berdo_id is null and g.upgrade_id <> 0 and g.meets_standard_at_start)
            as retrofit_compliant,
        any_value(g.upgrade_name) filter (where g.berdo_id = {CASE_ID}) as case_pick
    from g
    join energy_scenarios s using (scenario)
    left join already a on a.scenario = g.scenario and a.berdo_id = g.berdo_id
    where g.cost_rank_mid = 1
    group by g.scenario, g.perspective
    order by ord, g.perspective
    """,
)

be = [r["breakeven_acp_usd_per_t"] for r in rows(f"select * from read_csv('{OUT / 'breakeven.csv'}')")]
be.sort()
d = rows(
    f"""
    select count(*) as matched,
        count(*) filter (where not meets_standard_without_upgrade) as over_limit,
        count(*) filter (where not meets_standard_without_upgrade and recommended_upgrade_id = 0) as over_acp_5yr,
        count(*) filter (where is_robust_to_cost) as robust_to_cost
    from berdo_decisions
    """
)[0]
case = rows(f"select building_address, gfa_sqft, baseline_ghg_intensity_kgco2e_sqft from berdo_decisions where berdo_id = {CASE_ID}")[0]
stats = {
    **d,
    "with_compliant_option": len(be),
    "breakeven_le_current": sum(x <= acp for x in be),
    "breakeven_median": be[len(be) // 2] if len(be) % 2 else (be[len(be) // 2 - 1] + be[len(be) // 2]) / 2,
    "acp_usd_per_t": acp,
    "case_address": case["building_address"],
    "case_gfa_sqft": round(case["gfa_sqft"]),
    "case_intensity": round(case["baseline_ghg_intensity_kgco2e_sqft"], 2),
}
(OUT / "stats.json").write_text(json.dumps(stats, indent=2) + "\n")
print(json.dumps(stats, indent=2))
