-- One row per ComStock model per census tract (Suffolk County, baseline/upgrade0): the same
-- bldg_id repeats across tracts with a tract-specific `weight`. ComStock is synthetic:
-- `weight` is how many real buildings the model stands for in that tract. calc.weighted.* columns
-- are weight * per-building values, so divide the weight back out.
with raw as (
    select * from read_parquet('{{ var("comstock_url") }}')
)

select
    bldg_id || '-' || "in.nhgis_tract_gisjoin" as comstock_key,
    bldg_id as comstock_id,
    "in.nhgis_tract_gisjoin" as tract_gisjoin,
    weight,
    "in.comstock_building_type" as comstock_type,
    "in.sqft..ft2" as gfa_sqft,
    try_cast("in.year_built" as integer) as year_built,
    "in.heating_fuel" as heating_fuel,
    "out.site_energy.total.energy_consumption_intensity..kwh_per_ft2" * 3.412 as eui_kbtu_sqft,
    "calc.weighted.electricity.total.energy_consumption..tbtu" / weight * 1e9 as electricity_kbtu,
    "calc.weighted.natural_gas.total.energy_consumption..tbtu" / weight * 1e9 as natural_gas_kbtu,
    (
        coalesce("calc.weighted.fuel_oil.total.energy_consumption..tbtu", 0)
        + coalesce("calc.weighted.propane.total.energy_consumption..tbtu", 0)
    ) / weight * 1e9 as oil_propane_kbtu,
    coalesce("calc.weighted.district_heating.total.energy_consumption..tbtu", 0)
        / weight * 1e9 as district_heating_kbtu,
    -- eGRID 2021 subregion factors; BERDO uses Boston-specific factors, so compare loosely
    "calc.weighted.emissions.total_with_egrid..co2e_mmt" / weight * 1e9 as ghg_kgco2e
from raw
