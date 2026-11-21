-- Every option's 20-year cost for Report 2's case study, 24-32 Farnsworth St (BERDO 106476),
-- from the owner's and society's views (projected scenario, mid energy prices, BTB mid costs).
-- Writes analysis_outputs/case_study_106476.csv.
-- Grain: perspective x option.
{{ config(post_hook="{{ export_csv('case_study_106476.csv', 'perspective, global_cost_mid_usd') }}") }}

select
    perspective,
    upgrade_id,
    upgrade_name,
    meets_standard_at_start,
    years_over_limit,
    round(global_cost_mid_usd, 2) as global_cost_mid_usd,
    round(savings_vs_no_upgrade_usd, 2) as savings_vs_no_upgrade_usd,
    cost_rank_mid
from {{ ref('berdo_global_cost') }}
where berdo_id = 106476 and scenario = 'projected' and energy_price = 'mid'
