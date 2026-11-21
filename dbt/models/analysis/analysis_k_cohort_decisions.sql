-- The five-year decision at each k for the offices over the var("decision_period_start")
-- limit without a retrofit. Writes analysis_outputs/k_sensitivity/data/full_k_decisions.csv.
-- Grain: k x office.
-- Values are rounded (costs to the cent, the rest to 9 decimals) so that float noise from
-- parallel sums doesn't change the CSV between identical builds.
{{ config(post_hook="{{ export_csv('k_sensitivity/data/full_k_decisions.csv', 'k, berdo_id') }}") }}

select
    k,
    berdo_id,
    recommended_upgrade_id,
    recommended_option,
    meets_standard,
    round(projected_ghg_intensity_kgco2e_sqft, 9) as projected_ghg_intensity_kgco2e_sqft,
    round(installed_cost_mid_usd, 2) as installed_cost_mid_usd,
    round(period_acp_usd, 2) as period_acp_usd,
    round(period_energy_cost_usd, 2) as period_energy_cost_usd,
    round(total_cost_mid_usd, 2) as total_cost_mid_usd
from {{ ref('analysis_k_decisions') }}
where not meets_standard_without_upgrade
