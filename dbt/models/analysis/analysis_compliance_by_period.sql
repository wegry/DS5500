-- Compliance in the first year of each standards period (var("decision_period_start") and
-- var("later_period_starts")) under projected grid factors, mid prices, and BTB mid costs.
-- The retrofit is chosen once, in var("horizon_start"), by 20-year global cost; this counts,
-- for the offices over each period's limit with no retrofit, how many have an option that
-- meets it and whether each perspective's cheapest option does. Writes
-- analysis_outputs/compliance_by_period.csv.
-- Grain: period.
{{ config(post_hook="{{ export_csv('compliance_by_period.csv', 'period_start') }}") }}

{%- set years = [var("decision_period_start")] + var("later_period_starts") %}

with g as (
    select * from {{ ref('berdo_global_cost') }}
    where scenario = 'projected' and energy_price = 'mid'
),

-- one row per option, perspective, and period
checks as (
    select
        berdo_id, upgrade_id, perspective, cost_rank_mid,
        unnest([{{ years | join(", ") }}]) as period_start,
        unnest([meets_standard_at_start
            {%- for yr in var("later_period_starts") %}, meets_standard_{{ yr }}{% endfor %}]) as meets
    from g
),

at_risk as (
    select period_start, berdo_id from checks
    where upgrade_id = 0 and perspective = 'financial' and not meets
)

select
    c.period_start,
    any_value(s.standard_kgco2e_sqft) as office_standard_kgco2e_sqft,
    count(distinct c.berdo_id) as offices_over_limit,
    count(distinct c.berdo_id) filter (where c.meets) as has_compliant_option,
    count(*) filter (where c.perspective = 'financial' and c.cost_rank_mid = 1 and c.meets)
        as owner_choice_compliant,
    count(*) filter (where c.perspective = 'societal' and c.cost_rank_mid = 1 and c.meets)
        as societal_choice_compliant
from checks as c
inner join at_risk using (period_start, berdo_id)
inner join {{ ref('berdo_emissions_standards') }} as s
    on s.building_use = 'Office' and s.period_start = c.period_start
group by c.period_start
