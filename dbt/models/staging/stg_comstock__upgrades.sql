-- One row per ComStock model x census tract x upgrade (Suffolk County). The same bldg_id
-- repeats across tracts with a tract-specific `weight`: how many real buildings the
-- synthetic model stands for there. Upgrade 0 is the baseline; where an upgrade does not
-- apply (applicability = false) the row carries baseline results.
-- calc.weighted.* columns are weight * per-building values, so divide the weight back out.
{%- set fuels = {
    "natural_gas": "natural_gas",
    "fuel_oil": "fuel_oil",
    "propane": "propane",
    "district_heating": "district_heating",
    "district_cooling": "district_cooling",
} %}
with raw as (
    select *
    from read_parquet([
        {%- for i in range(var("comstock_max_upgrade") + 1) %}
        '{{ var("comstock_dir") }}/{{ var("comstock_county_prefix") }}_upgrade{{ i }}_basic.parquet'{{ "," if not loop.last }}
        {%- endfor %}
    ], union_by_name = true)
),

per_building as (
    select
        bldg_id || '-' || "in.nhgis_tract_gisjoin" as comstock_key,
        bldg_id as comstock_id,
        "in.nhgis_tract_gisjoin" as tract_gisjoin,
        upgrade as upgrade_id,
        "in.upgrade_name" as upgrade_name,
        applicability,
        weight,
        "in.comstock_building_type" as comstock_type,
        "in.sqft..ft2" as gfa_sqft,
        try_cast("in.year_built" as integer) as year_built,
        "in.heating_fuel" as heating_fuel,
        "out.site_energy.total.energy_consumption_intensity..kwh_per_ft2" * 3.412 as eui_kbtu_sqft,
        -- purchased (net of onsite PV) to match BERDO's grid electricity, so PV upgrades count
        "out.electricity.purchased.energy_consumption..kwh" * 3.412 as electricity_kbtu,
        {% for col, f in fuels.items() -%}
        coalesce("calc.weighted.{{ f }}.total.energy_consumption..tbtu", 0) / weight * 1e9
            as {{ col }}_kbtu,
        {% endfor -%}
        -- eGRID 2021 subregion factors; BERDO uses Boston-specific factors, so compare loosely
        "calc.weighted.emissions.total_with_egrid..co2e_mmt" / weight * 1e9 as ghg_kgco2e
    from raw
)

select
    comstock_key || '-' || upgrade_id as comstock_upgrade_key,
    * exclude (fuel_oil_kbtu, propane_kbtu),
    fuel_oil_kbtu + propane_kbtu as oil_propane_kbtu
from per_building
