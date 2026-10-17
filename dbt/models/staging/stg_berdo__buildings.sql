-- One row per building/campus row in the BERDO disclosure.
-- all_varchar because the sparse fuel columns have no consistent type; cast explicitly.
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
    try_cast("Total Site Energy Usage (kBtu)" as double) as site_energy_kbtu,
    try_cast("Electricity Usage (kWh)" as double) * 3.412 as electricity_kbtu,
    try_cast("Natural Gas Usage (kBtu)" as double) as natural_gas_kbtu,
    try_cast("Total GHG Emissions (kgCO2e)" as double) as ghg_kgco2e,
    "Reporting Compliance Status" as reporting_status,
    "Emissions Compliance Status" as emissions_compliance_status,
    "Corresponding Campus ID" as campus_id,
    "Corresponding Portfolio ID" as portfolio_id
from raw
