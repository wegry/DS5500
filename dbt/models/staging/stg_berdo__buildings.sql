-- One row per building/campus row in the BERDO disclosure.
-- all_varchar because the sparse fuel columns have no consistent type; cast explicitly.
-- Energy is in kWh: BERDO reports electricity in kWh and every other fuel in kBtu.
{%- set oil_propane = [
    "Fuel Oil 1", "Fuel Oil 2", "Fuel Oil 4", "Fuel Oil 5 and 6",
    "Propane", "Diesel", "Kerosene",
] %}
with raw as (
    select *
    from read_xlsx(
        '{{ var("berdo_xlsx") }}',
        sheet = 'Buildings & Campuses',
        all_varchar = true
    )
)

select
    try_cast("BERDO ID" as bigint) as berdo_id,
    try_cast("Tax Parcel ID" as bigint) as tax_parcel_id,
    "Parcel Owner Name" as owner_name,
    "Building Address" as building_address,
    -- the portfolio sheet writes "College / University", this sheet "College/University"
    regexp_replace("Largest Property Type", '\s*/\s*', '/') as property_type,
    try_cast("Gross Floor Area (sq ft)" as double) as gfa_sqft,
    try_cast("Total Site Energy Usage (kBtu)" as double) / 3.412 as site_energy_kwh,
    coalesce(try_cast("Electricity Usage (kWh)" as double), 0) as electricity_kwh,
    coalesce(try_cast("Natural Gas Usage (kBtu)" as double), 0) / 3.412 as natural_gas_kwh,
    (
        coalesce(try_cast("District Hot Water Usage (kBtu)" as double), 0)
        + coalesce(try_cast("District Steam Usage (kBtu)" as double), 0)
    ) / 3.412 as district_heating_kwh,
    coalesce(try_cast("District Chilled Water Usage (kBtu)" as double), 0) / 3.412
        as district_cooling_kwh,
    (
        {% for f in oil_propane -%}
        coalesce(try_cast("{{ f }} Usage (kBtu)" as double), 0){{ " +" if not loop.last }}
        {% endfor -%}
    ) / 3.412 as oil_propane_kwh,
    try_cast("Total GHG Emissions (kgCO2e)" as double) as ghg_kgco2e,
    -- per-fuel emissions sum to the total
    coalesce(try_cast("Electricity Emissions (kgCO2e)" as double), 0) as electricity_ghg_kgco2e,
    coalesce(try_cast("Natural Gas Emissions (kgCO2e)" as double), 0) as natural_gas_ghg_kgco2e,
    coalesce(try_cast("District Hot Water Emissions (kgCO2e)" as double), 0)
        + coalesce(try_cast("District Steam Emissions (kgCO2e)" as double), 0)
        as district_heating_ghg_kgco2e,
    coalesce(try_cast("District Chilled Water Emissions (kgCO2e)" as double), 0)
        as district_cooling_ghg_kgco2e,
    {% for f in oil_propane -%}
    coalesce(try_cast("{{ f }} Emissions (kgCO2e)" as double), 0){{ " +" if not loop.last else " as oil_propane_ghg_kgco2e," }}
    {% endfor -%}
    try_cast("Applicable Emissions Compliance Standard (kgCO2e/sq ft)" as double)
        as compliance_standard_kgco2e_sqft,
    -- "2025", "2030", or "Exempt During Vacancy"
    try_cast("First Emissions Compliance Year" as integer) as first_compliance_year,
    "Reporting Compliance Status" as reporting_status,
    "Emissions Compliance Status" as emissions_compliance_status,
    "Corresponding Campus ID" as campus_id,
    "Corresponding Portfolio ID" as portfolio_id
from raw
