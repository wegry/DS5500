-- Leave-one-out prediction errors: the emissions reduction missed, in percentage points of
-- the held-out model's baseline, and the post-retrofit intensity missed, in kg CO2e / sq ft.
-- Grain: held-out model x weighting x district_rule x k x upgrade (models with baseline
-- emissions).
{{ config(materialized='view') }}

select
    *,
    100 * abs((actual_ghg - pred_ghg) / base_ghg) as err_pp,
    abs(actual_ghg - pred_ghg) / gfa_sqft as err_kg_sqft,
    100 * (1 - actual_ghg / base_ghg) as actual_reduction_pct,
    -- the configuration the project matches BERDO buildings with
    (weighting = '{{ var("match_weighting") }}' and district_rule = {{ var("match_district_rule") }})
        or k = 'type' as is_project_config
from {{ ref('analysis_loo_predictions') }}
where base_ghg > 0
