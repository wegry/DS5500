-- Signed leave-one-out errors at the project's configuration and var("match_k"), which the
-- Monte Carlo (monte_carlo_20year.py) samples. Positive = optimistic model.
-- The intensities and signed_error_pp count the electricity part at the decision year's
-- BERDO factor (int_berdo_electricity_index), as compliance does; the *_frac split is at
-- 2025 factors, so the Monte Carlo can scale the electricity part by each year's index.
-- Values are rounded to 9 decimals (+ 0.0 turns -0.0 into 0.0) so that float noise from
-- parallel sums doesn't change the CSV between identical builds.
-- Writes analysis_outputs/loo_residuals.csv (not tracked).
-- Grain: held-out model x upgrade.
{{ config(post_hook="{{ export_csv('loo_residuals.csv', 'held_out_model_id, upgrade_id') }}") }}

with e as (
    select
        e.*,
        ix.year as decision_year,
        -- each emissions total at the decision year's electricity factor
        e.base_ghg - e.base_elec_ghg * (1 - ix.electricity_index) as base_dy,
        e.pred_ghg - e.pred_elec_ghg * (1 - ix.electricity_index) as pred_dy,
        e.actual_ghg - e.actual_elec_ghg * (1 - ix.electricity_index) as actual_dy
    from {{ ref('analysis_loo_errors') }} as e
    inner join {{ ref('int_berdo_electricity_index') }} as ix
        on ix.year = {{ var("decision_period_start") }}
    where e.is_project_config and e.k = '{{ var("match_k") }}' and e.gfa_sqft > 0
)

select
    held_out_id as held_out_model_id,
    comstock_type,
    upgrade_id,
    gfa_sqft,
    decision_year,
    round(base_dy / gfa_sqft, 9) + 0.0 as baseline_intensity_kgco2e_sqft,
    round(pred_dy / gfa_sqft, 9) + 0.0 as predicted_intensity_kgco2e_sqft,
    round(actual_dy / gfa_sqft, 9) + 0.0 as actual_intensity_kgco2e_sqft,
    round((actual_dy - pred_dy) / gfa_sqft, 9) + 0.0 as signed_error_kgco2e_sqft,
    round(100 * (actual_dy - pred_dy) / nullif(base_dy, 0), 9) + 0.0 as signed_error_pp,
    round((actual_elec_ghg - pred_elec_ghg) / base_ghg, 9) + 0.0 as signed_error_elec_frac,
    round(((actual_ghg - actual_elec_ghg) - (pred_ghg - pred_elec_ghg)) / base_ghg, 9) + 0.0
        as signed_error_other_frac
from e
