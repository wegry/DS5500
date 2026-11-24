-- Each retrofit option across the offices over the var("decision_period_start") limit with
-- no retrofit (projected scenario, mid energy prices, BTB mid costs): how many it applies
-- to, its median installed cost per square foot and median modeled cut in 2030 emissions
-- intensity, how many it brings under the 2030 limit, and how often it is the cheapest
-- 20-year option from each perspective, and compliant when it is. Ties are broken as in
-- the k-sensitivity audit: cost rounded to cents, then the lower upgrade ID. Writes
-- analysis_outputs/option_summary.csv.
-- Grain: upgrade (no retrofit is upgrade 0).
{{ config(post_hook="{{ export_csv('option_summary.csv', 'upgrade_id') }}") }}

with g as (
    select *
    from {{ ref('berdo_global_cost') }}
    where scenario = 'projected' and energy_price = 'mid'
),

cohort as (
    select berdo_id from g
    where perspective = 'financial' and upgrade_id = 0 and not meets_standard_at_start
),

ranked as (
    select
        g.*,
        row_number() over (
            partition by perspective, berdo_id
            order by round(global_cost_mid_usd, 2), upgrade_id
        ) as cost_rank
    from g
    inner join cohort using (berdo_id)
),

intensity as (
    select berdo_id, upgrade_id, projected_ghg_intensity_kgco2e_sqft as intensity
    from {{ ref('berdo_upgrade_compliance') }}
    where period_start = {{ var("decision_period_start") }}
),

options as (
    select
        r.upgrade_id,
        any_value(r.upgrade_name) as upgrade_name,
        count(*) as applicable_offices,
        median(r.installed_cost_mid_usd / b.gfa_sqft) as median_installed_usd_sqft,
        median(100 * (1 - i.intensity / i0.intensity)) as median_cut_2030_pct,
        count(*) filter (where r.meets_standard_at_start) as meets_2030
    from ranked as r
    inner join {{ ref('int_berdo_match_buildings') }} as b using (berdo_id)
    inner join intensity as i using (berdo_id, upgrade_id)
    inner join intensity as i0 on i0.berdo_id = r.berdo_id and i0.upgrade_id = 0
    where r.perspective = 'financial'
    group by r.upgrade_id
),

picks as (
    select
        upgrade_id,
        count(*) filter (where perspective = 'financial') as owner_picks,
        count(*) filter (where perspective = 'financial' and meets_standard_at_start)
            as owner_picks_compliant,
        count(*) filter (where perspective = 'societal') as societal_picks,
        count(*) filter (where perspective = 'societal' and meets_standard_at_start)
            as societal_picks_compliant
    from ranked
    where cost_rank = 1
    group by upgrade_id
)

select
    o.*,
    coalesce(p.owner_picks, 0) as owner_picks,
    coalesce(p.owner_picks_compliant, 0) as owner_picks_compliant,
    coalesce(p.societal_picks, 0) as societal_picks,
    coalesce(p.societal_picks_compliant, 0) as societal_picks_compliant
from options as o
left join picks as p using (upgrade_id)
