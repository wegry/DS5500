-- The var("match_k") nearest ComStock baseline models for each BERDO building, among the
-- ComStock types its property type maps to. Distance: log size gap + log EUI gap + half
-- the L1 gap between fuel shares (the three terms are kept for match-quality checks).
-- var("match_w_size"/"match_w_eui"/"match_w_fuel") weight the terms (1 each by default), and
-- var("match_district_rule") restricts candidates to models whose district-energy use (any
-- vs none) agrees with the building's; metric_sensitivity.py compares these choices.
-- var("match_weighting") sets how much each neighbor counts when downstream models pool
-- them: equally (unweighted) or by 1 / (distance + 1e-6) (inverse_distance).
{% set weighting = var("match_weighting", "unweighted") %}
{% if weighting not in ["unweighted", "inverse_distance"] %}
    {{ exceptions.raise_compiler_error("match_weighting must be 'unweighted' or 'inverse_distance'") }}
{% endif %}
with models as (
    select
        *,
        electricity_kwh + natural_gas_kwh + district_heating_kwh
            + district_cooling_kwh + oil_propane_kwh as fuel_total_kwh
    from {{ ref('int_comstock_models') }}
    where upgrade_id = 0
),

candidates as (
    select
        b.berdo_id,
        m.comstock_id,
        m.comstock_type,
        abs(ln(b.gfa_sqft / m.gfa_sqft)) as size_gap,
        abs(ln(b.eui_kwh_sqft / m.eui_kwh_sqft)) as eui_gap,
        0.5 * (
            abs(b.electricity_share - m.electricity_kwh / m.fuel_total_kwh)
            + abs(b.natural_gas_share - m.natural_gas_kwh / m.fuel_total_kwh)
            + abs(b.district_share
                - (m.district_heating_kwh + m.district_cooling_kwh) / m.fuel_total_kwh)
            + abs(b.oil_propane_share - m.oil_propane_kwh / m.fuel_total_kwh)
        ) as fuel_share_gap
    from {{ ref('int_berdo_match_buildings') }} as b
    inner join {{ ref('berdo_comstock_type_crosswalk') }} as cw
        on b.property_type = cw.berdo_type
    inner join models as m
        on cw.comstock_type = m.comstock_type
    {%- if var("match_district_rule", false) %}
    where (b.district_share > 0)
        = (m.district_heating_kwh + m.district_cooling_kwh > 0)
    {%- endif %}
),

weighted as (
    select
        *,
        {{ var("match_w_size", 1) }} * size_gap
            + {{ var("match_w_eui", 1) }} * eui_gap
            + {{ var("match_w_fuel", 1) }} * fuel_share_gap as distance
    from candidates
)

select
    berdo_id || '-' || comstock_id as match_key,
    *,
    {% if weighting == "inverse_distance" -%}
    1.0 / (distance + 0.000001) as match_weight,
    {%- else -%}
    1.0 as match_weight,
    {%- endif %}
    -- the matching settings, so Python checks (loo_validation.py) can mirror this build
    '{{ weighting }}' as match_weighting,
    {{ var("match_district_rule", false) }} as match_district_rule,
    row_number() over (partition by berdo_id order by distance, comstock_id) as match_rank
from weighted
qualify match_rank <= {{ var("match_k") }}
