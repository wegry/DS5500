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
    b.*,
    -- the disclosed Site EUI column is ~19x below energy / GFA, so derive it
    b.fuel_total_kwh / b.gfa_sqft as eui_kwh_sqft,
    b.ghg_kgco2e / b.gfa_sqft as ghg_intensity_kgco2e_sqft,
    b.electricity_kwh / b.fuel_total_kwh as electricity_share,
    b.natural_gas_kwh / b.fuel_total_kwh as natural_gas_share,
    (b.district_heating_kwh + b.district_cooling_kwh) / b.fuel_total_kwh as district_share,
    b.oil_propane_kwh / b.fuel_total_kwh as oil_propane_share,
    -- estimated from footprints and roof heights; null where the parcel has no footprint
    s.stories,
    s.stories_source
from buildings as b
left join {{ ref('int_berdo_building_stories') }} as s using (berdo_id)
where b.fuel_total_kwh > 0
