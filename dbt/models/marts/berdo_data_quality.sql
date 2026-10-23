-- Missing and inconsistent values for BERDO buildings of var("match_property_types"), and
-- whether each made it into the matched set (int_berdo_match_buildings).
-- Grain: one row per BERDO building of those property types.
with buildings as (
    select
        *,
        electricity_kwh + natural_gas_kwh + district_heating_kwh
            + district_cooling_kwh + oil_propane_kwh as fuel_total_kwh,
        electricity_ghg_kgco2e + natural_gas_ghg_kgco2e + district_heating_ghg_kgco2e
            + district_cooling_ghg_kgco2e + oil_propane_ghg_kgco2e as fuel_ghg_total_kgco2e
    from {{ ref('stg_berdo__buildings') }}
    where property_type in (
        {%- for t in var("match_property_types") %}'{{ t }}'{{ ", " if not loop.last }}{% endfor -%}
    )
      and berdo_id is not null
)

select
    berdo_id,
    owner_name,
    building_address,
    property_type,
    reporting_status,
    emissions_compliance_status,
    first_compliance_year,
    gfa_sqft,
    -- mostly buildings reporting at the portfolio or campus level, or still pending
    ghg_kgco2e is null as is_missing_ghg,
    gfa_sqft is null or gfa_sqft <= 0 as is_missing_gfa,
    site_energy_kwh is null as is_missing_site_energy,
    coalesce(fuel_total_kwh, 0) <= 0 as has_no_fuel_use,
    compliance_standard_kgco2e_sqft is null as is_missing_standard,
    -- fuels should add up to the disclosed totals; flag gaps over 1%
    coalesce(abs(fuel_total_kwh / nullif(site_energy_kwh, 0) - 1) > 0.01, false)
        as is_fuel_energy_inconsistent,
    coalesce(abs(fuel_ghg_total_kgco2e / nullif(ghg_kgco2e, 0) - 1) > 0.01, false)
        as is_fuel_ghg_inconsistent,
    berdo_id in (select berdo_id from {{ ref('int_berdo_match_buildings') }}) as is_matched
from buildings
