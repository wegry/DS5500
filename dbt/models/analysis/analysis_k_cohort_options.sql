-- Every option at each k for the offices in analysis_k_cohort_decisions. Writes
-- analysis_outputs/k_sensitivity/data/full_k_options.csv.
-- Grain: k x office x option.
-- Values are rounded (costs to the cent, the rest to 9 decimals) so that float noise from
-- parallel sums doesn't change the CSV between identical builds.
{{ config(post_hook="{{ export_csv('k_sensitivity/data/full_k_options.csv', 'k, berdo_id, upgrade_id') }}") }}

select
    o.k,
    o.berdo_id,
    o.upgrade_id,
    o.upgrade_name,
    o.meets_standard,
    round(o.applicable_share, 9) as applicable_share,
    round(o.installed_cost_mid_usd, 2) as installed_cost_mid_usd,
    round(o.capital_charged_mid_usd, 2) as capital_charged_mid_usd,
    round(o.existing_hvac_charged_mid_usd, 2) as existing_hvac_charged_mid_usd,
    round(o.period_acp_usd, 2) as period_acp_usd,
    round(o.period_energy_cost_usd, 2) as period_energy_cost_usd,
    round(o.total_cost_mid_usd, 2) as total_cost_mid_usd,
    round(o.projected_ghg_intensity_kgco2e_sqft, 9) as projected_ghg_intensity_kgco2e_sqft
from {{ ref('analysis_k_decision_options') }} as o
inner join {{ ref('analysis_k_cohort_decisions') }} as d using (k, berdo_id)
