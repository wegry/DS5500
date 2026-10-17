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
    avg(eui_kbtu_sqft) as eui_kbtu_sqft,
    avg(electricity_kbtu) as electricity_kbtu,
    avg(natural_gas_kbtu) as natural_gas_kbtu,
    avg(oil_propane_kbtu) as oil_propane_kbtu,
    avg(district_heating_kbtu) as district_heating_kbtu,
    avg(district_cooling_kbtu) as district_cooling_kbtu,
    avg(ghg_kgco2e) as ghg_kgco2e
from {{ ref('stg_comstock__upgrades') }}
group by comstock_id, upgrade_id
