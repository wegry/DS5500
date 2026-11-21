-- The 20-year picks at each k for the offices over the var("decision_period_start") limit
-- without a retrofit (projected scenario, mid prices, BTB mid costs): the cheapest option and
-- the cheapest one that meets the standard at the start, if any. Writes
-- analysis_outputs/k_sensitivity/data/global_k_choices.csv.
-- Grain: k x perspective x office.
{{ config(post_hook="{{ export_csv('k_sensitivity/data/global_k_choices.csv', 'perspective, k, berdo_id') }}") }}

with g as (
    select * from {{ ref('analysis_k_global_cost') }}
),

cohort as (
    select distinct berdo_id
    from g
    where upgrade_id = 0 and not meets_standard_at_start
),

compliant as (
    select
        k,
        perspective,
        berdo_id,
        upgrade_id,
        global_cost_mid_usd,
        -- ties to the cent go to the lower upgrade id, as in berdo_global_cost's cost_rank_mid
        row_number() over (
            partition by k, perspective, berdo_id
            order by round(global_cost_mid_usd, 2), upgrade_id
        ) as rank
    from g
    where meets_standard_at_start
)

select
    b.k,
    b.perspective,
    b.berdo_id,
    b.upgrade_id as cheapest_upgrade_id,
    b.meets_standard_at_start as cheapest_meets_standard,
    round(b.global_cost_mid_usd, 2) as cheapest_global_cost_usd,
    c.upgrade_id as cheapest_compliant_upgrade_id,
    round(c.global_cost_mid_usd, 2) as cheapest_compliant_global_cost_usd
from g as b
inner join cohort using (berdo_id)
left join compliant as c
    on c.k = b.k and c.perspective = b.perspective and c.berdo_id = b.berdo_id and c.rank = 1
where b.cost_rank_mid = 1
