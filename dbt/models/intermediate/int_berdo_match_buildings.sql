-- BERDO buildings of var("match_property_types") that report their own energy and GHG,
-- with the features used to match them to ComStock models.
with buildings as (
    select
        *,
        electricity_kwh + natural_gas_kwh + district_heating_kwh
            + district_cooling_kwh + oil_propane_kwh as fuel_total_kwh
    from {{ ref('stg_berdo__buildings') }}
    where property_type in (
        {%- for t in var("match_property_types") %}'{{ t }}'{{ ", " if not loop.last }}{% endfor -%}
    )
      and berdo_id is not null
      and ghg_kgco2e is not null
      and gfa_sqft > 0
)

select
    *,
    -- the disclosed Site EUI column is ~19x below energy / GFA, so derive it
    fuel_total_kwh / gfa_sqft as eui_kwh_sqft,
    ghg_kgco2e / gfa_sqft as ghg_intensity_kgco2e_sqft,
    electricity_kwh / fuel_total_kwh as electricity_share,
    natural_gas_kwh / fuel_total_kwh as natural_gas_share,
    (district_heating_kwh + district_cooling_kwh) / fuel_total_kwh as district_share,
    oil_propane_kwh / fuel_total_kwh as oil_propane_share
from buildings
where fuel_total_kwh > 0
