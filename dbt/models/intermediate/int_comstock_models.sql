-- One row per ComStock model x upgrade. Per-building results are identical across the
-- tracts a model is sampled into, so collapse tracts and sum their weights.
select
    comstock_id,
    upgrade_id,
    any_value(upgrade_name) as upgrade_name,
    bool_or(applicability) as applicability,
    any_value(comstock_type) as comstock_type,
    any_value(gfa_sqft) as gfa_sqft,
    any_value(year_built) as year_built,
    any_value(heating_fuel) as heating_fuel,
    sum(weight) as weight,
    avg(eui_kwh_sqft) as eui_kwh_sqft,
    avg(electricity_kwh) as electricity_kwh,
    avg(natural_gas_kwh) as natural_gas_kwh,
    avg(oil_propane_kwh) as oil_propane_kwh,
    avg(district_heating_kwh) as district_heating_kwh,
    avg(district_cooling_kwh) as district_cooling_kwh,
    avg(ghg_kgco2e) as ghg_kgco2e
from {{ ref('stg_comstock__upgrades') }}
group by comstock_id, upgrade_id
