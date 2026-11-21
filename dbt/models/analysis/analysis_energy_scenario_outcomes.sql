-- The cheapest 20-year option under each energy scenario (energy_scenarios seed) at mid
-- prices and BTB mid costs, for the offices over the var("decision_period_start") limit at
-- today's grid factor: how many fall under the limit with no retrofit once BERDO's factor
-- falls, and, for the rest, whether the cheapest option is no retrofit, a retrofit still
-- over the limit, or a compliant one. Writes analysis_outputs/energy_scenario_outcomes.csv.
-- Grain: scenario x perspective.
{{ config(post_hook="{{ export_csv('energy_scenario_outcomes.csv', 'scenario, perspective') }}") }}

with g as (
    select * from {{ ref('berdo_global_cost') }} where energy_price = 'mid'
),

-- over the limit with no retrofit when nothing changes from 2025
cohort as (
    select berdo_id from g
    where scenario = 'frozen' and perspective = 'financial' and upgrade_id = 0
      and not meets_standard_at_start
),

-- under the limit with no retrofit, as BERDO counts emissions in each scenario
already as (
    select scenario, berdo_id from g
    where upgrade_id = 0 and perspective = 'financial' and meets_standard_at_start
)

select
    g.scenario,
    any_value(s.label) as label,
    g.perspective,
    count(*) as offices,
    count(*) filter (where a.berdo_id is not null) as under_limit_anyway,
    count(*) filter (where a.berdo_id is null and g.upgrade_id = 0) as no_retrofit,
    count(*) filter (where a.berdo_id is null and g.upgrade_id <> 0 and not g.meets_standard_at_start)
        as retrofit_over,
    count(*) filter (where a.berdo_id is null and g.upgrade_id <> 0 and g.meets_standard_at_start)
        as retrofit_compliant
from g
inner join cohort using (berdo_id)
inner join {{ ref('energy_scenarios') }} as s using (scenario)
left join already as a on a.scenario = g.scenario and a.berdo_id = g.berdo_id
where g.cost_rank_mid = 1
group by g.scenario, g.perspective
