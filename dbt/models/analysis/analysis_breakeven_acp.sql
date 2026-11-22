-- The ACP rate at which each over-limit office's cheapest 20-year option, from the owner's
-- view, first meets the var("decision_period_start") standard (projected scenario, mid energy
-- prices, BTB mid costs). Global cost is linear in the ACP rate: fixed costs plus the rate
-- times the present value of tons over the limit. A compliant option a is cheapest on the
-- interval [lo, hi] where it beats every other option b; the break-even rate is the lowest
-- lo over the compliant options. Offices with no compliant option don't appear. Writes
-- analysis_outputs/breakeven_acp.csv.
-- Grain: over-limit office with a compliant option.
{{ config(post_hook="{{ export_csv('breakeven_acp.csv', 'breakeven_acp_usd_per_t, berdo_id') }}") }}

with g as (
    select
        berdo_id,
        upgrade_id,
        meets_standard_at_start as ok,
        -- rounded so options that differ only by floating-point noise (Packages 2 and 4
        -- often cost the same) compare as exact ties below
        round(global_cost_mid_usd - emissions_cost_pv_usd, 2) as fixed_usd,
        -- present value of tons over the limit, i.e. dollars per $1/t of ACP
        round(emissions_cost_pv_usd / {{ var("acp_usd_per_tco2e") }}, 6) as excess_t
    from {{ ref('berdo_global_cost') }}
    where perspective = 'financial' and energy_price = 'mid' and scenario = 'projected'
),

cohort as (
    select berdo_id from g where upgrade_id = 0 and not ok
),

bounds as (
    select
        a.berdo_id,
        a.upgrade_id,
        greatest(0, coalesce(max(case when b.excess_t > a.excess_t
            then (a.fixed_usd - b.fixed_usd) / (b.excess_t - a.excess_t) end), 0)) as lo,
        coalesce(min(case when b.excess_t < a.excess_t
            then (b.fixed_usd - a.fixed_usd) / (a.excess_t - b.excess_t) end), 1e12) as hi,
        -- an option with the same excess tons must also be no dearer
        bool_and(b.excess_t <> a.excess_t or a.fixed_usd <= b.fixed_usd) as tie_ok
    from g as a
    inner join g as b on b.berdo_id = a.berdo_id and b.upgrade_id <> a.upgrade_id
    inner join cohort as c on c.berdo_id = a.berdo_id
    where a.ok
    group by a.berdo_id, a.upgrade_id
)

select
    berdo_id,
    round(min(lo), 2) as breakeven_acp_usd_per_t,
    -- ties (e.g. Packages 2 and 4 at identical cost) go to the lower upgrade ID
    arg_min(upgrade_id, (round(lo, 2), upgrade_id)) as upgrade_id_at_breakeven
from bounds
where lo <= hi and tie_ok
group by berdo_id
