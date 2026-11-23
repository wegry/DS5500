-- Every option's 20-year cost for Report 2's case study, 24-32 Farnsworth St (BERDO 106476),
-- from the owner's and society's views (projected scenario, mid energy prices, BTB mid costs).
-- Writes analysis_outputs/case_study_106476.csv.
-- Grain: perspective x option.
{{ config(post_hook="{{ export_csv('case_study_106476.csv', 'perspective, global_cost_mid_usd') }}") }}

select
    g.perspective,
    g.upgrade_id,
    g.upgrade_name,
    g.meets_standard_at_start,
    g.years_over_limit,
    round(g.global_cost_mid_usd, 2) as global_cost_mid_usd,
    round(g.savings_vs_no_upgrade_usd, 2) as savings_vs_no_upgrade_usd,
    g.cost_rank_mid,
    g.installed_cost_mid_usd,
    c.projected_ghg_intensity_kgco2e_sqft as projected_intensity_kgco2e_sqft
from {{ ref('berdo_global_cost') }} g
inner join {{ ref('berdo_upgrade_compliance') }} c
    on g.berdo_id = c.berdo_id and g.upgrade_id = c.upgrade_id
    and c.period_start = {{ var('decision_period_start') }}
where g.berdo_id = 106476 and g.scenario = 'projected' and g.energy_price = 'mid'
