-- BERDO buildings for the school selected by var("school_pattern"), with their portfolio.
-- Rows without a BERDO ID are owner-level placeholders with no address, so they are dropped.
select
    b.berdo_id,
    b.tax_parcel_id,
    b.owner_name,
    b.building_address,
    b.campus_id,
    b.portfolio_id,
    b.reporting_status,
    b.property_type as building_property_type,
    b.gfa_sqft as building_gfa_sqft,
    b.site_energy_kbtu as building_site_energy_kbtu,
    b.site_energy_kbtu / nullif(b.gfa_sqft, 0) as building_eui_kbtu_sqft,
    p.property_type as portfolio_property_type,
    p.gfa_sqft as portfolio_gfa_sqft,
    p.ghg_kgco2e as portfolio_ghg_kgco2e,
    p.ghg_intensity_kgco2e_sqft as portfolio_ghg_intensity_kgco2e_sqft,
    p.compliance_standard_kgco2e_sqft as portfolio_standard_kgco2e_sqft,
    -- building values are null when a portfolio files for its buildings together
    coalesce(b.property_type, p.property_type) as match_property_type
from {{ ref('stg_berdo__buildings') }} as b
left join {{ ref('stg_berdo__portfolios') }} as p using (portfolio_id)
where b.owner_name ilike '%{{ var("school_pattern") }}%'
  and b.berdo_id is not null
