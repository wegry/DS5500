-- BERDO buildings of var("match_property_types") that report their own energy and GHG,
-- with the features used to match them to ComStock models.
with buildings as (
    select
        *,
        electricity_kbtu + natural_gas_kbtu + district_heating_kbtu
            + district_cooling_kbtu + oil_propane_kbtu as fuel_total_kbtu
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
    fuel_total_kbtu / gfa_sqft as eui_kbtu_sqft,
    ghg_kgco2e / gfa_sqft as ghg_intensity_kgco2e_sqft,
    electricity_kbtu / fuel_total_kbtu as electricity_share,
    natural_gas_kbtu / fuel_total_kbtu as natural_gas_share,
    (district_heating_kbtu + district_cooling_kbtu) / fuel_total_kbtu as district_share,
    oil_propane_kbtu / fuel_total_kbtu as oil_propane_share
from buildings
where fuel_total_kbtu > 0
