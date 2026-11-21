{#- The BERDO-ComStock match distance, shared by the matching (int_berdo_comstock_matches)
    and the leave-one-out validation (analysis_loo_*), so the two cannot drift apart. -#}

{#- Baseline (upgrade 0) ComStock models with the features the distance compares: floor
    area, EUI, fuel shares and stories, as int_berdo_match_buildings has them for BERDO. -#}
{% macro comstock_match_features() -%}
select
    *,
    electricity_kwh / fuel_total_kwh as electricity_share,
    natural_gas_kwh / fuel_total_kwh as natural_gas_share,
    (district_heating_kwh + district_cooling_kwh) / fuel_total_kwh as district_share,
    oil_propane_kwh / fuel_total_kwh as oil_propane_share,
    district_heating_kwh + district_cooling_kwh > 0 as uses_district
from (
    select
        *,
        electricity_kwh + natural_gas_kwh + district_heating_kwh
            + district_cooling_kwh + oil_propane_kwh as fuel_total_kwh
    from {{ ref('int_comstock_models') }}
    where upgrade_id = 0
)
{%- endmacro %}

{#- The four distance terms between building `a` and model `c`: |ln size ratio|, |ln EUI
    ratio|, half the L1 gap in fuel shares, and |ln stories ratio| (0 when `a` has no
    stories estimate, so it does not affect that building's ranking). -#}
{% macro match_gaps(a, c) -%}
abs(ln({{ a }}.gfa_sqft / {{ c }}.gfa_sqft)) as size_gap,
abs(ln({{ a }}.eui_kwh_sqft / {{ c }}.eui_kwh_sqft)) as eui_gap,
0.5 * (
    abs({{ a }}.electricity_share - {{ c }}.electricity_share)
    + abs({{ a }}.natural_gas_share - {{ c }}.natural_gas_share)
    + abs({{ a }}.district_share - {{ c }}.district_share)
    + abs({{ a }}.oil_propane_share - {{ c }}.oil_propane_share)
) as fuel_share_gap,
coalesce(abs(ln({{ a }}.stories / {{ c }}.stories)), 0) as stories_gap
{%- endmacro %}

{#- The distance: the terms of match_gaps weighted by var("match_w_*"), 1 each by default. -#}
{% macro match_distance() -%}
{{ var("match_w_size", 1) }} * size_gap
    + {{ var("match_w_eui", 1) }} * eui_gap
    + {{ var("match_w_fuel", 1) }} * fuel_share_gap
    + {{ var("match_w_stories", 1) }} * stories_gap
{%- endmacro %}

{#- Neighbor weight when matched models are pooled: var("match_weighting") is unweighted
    (1 each) or inverse_distance (1 / (distance + 1e-6)). -#}
{% macro match_weight(weighting, distance="distance") -%}
{%- if weighting == "inverse_distance" -%}
1.0 / ({{ distance }} + 0.000001)
{%- elif weighting == "unweighted" -%}
1.0
{%- else -%}
{{ exceptions.raise_compiler_error("match_weighting must be 'unweighted' or 'inverse_distance'") }}
{%- endif -%}
{%- endmacro %}
