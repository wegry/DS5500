-- One row per BERDO building portfolio (owners can comply across buildings).
with raw as (
    select *
    from read_xlsx(
        '{{ var("berdo_xlsx") }}',
        sheet = 'Building Portfolios',
        all_varchar = true
    )
)

select
    "Portfolio ID" as portfolio_id,
    "Portfolio Owner Name" as portfolio_owner_name,
    regexp_replace("Largest Property Type", '\s*/\s*', '/') as property_type,
    try_cast("Gross Floor Area (sq ft)" as double) as gfa_sqft,
    try_cast("Total GHG Emissions (kgCO2e)" as double) as ghg_kgco2e,
    try_cast("GHG Emissions Intensity (kgCO2e/sq ft)" as double) as ghg_intensity_kgco2e_sqft,
    try_cast("Applicable Emissions Compliance Standard (kgCO2e/sq ft)" as double)
        as compliance_standard_kgco2e_sqft,
    "Emissions Compliance Status" as emissions_compliance_status,
    try_cast("First Emissions Compliance Year" as integer) as first_compliance_year
from raw
