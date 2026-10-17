-- BERDO x ComStock for one school. ComStock is synthetic, so there is no key to join on:
-- each BERDO building is paired with every ComStock building type its BERDO property type
-- maps to (see the crosswalk seed), and the ComStock side is that type's archetype.
-- Grain: one row per BERDO building x candidate ComStock type.
select
    b.berdo_id || '-' || c.comstock_type as match_key,
    b.berdo_id,
    b.tax_parcel_id,
    b.owner_name,
    b.building_address,
    b.campus_id,
    b.portfolio_id,
    b.reporting_status,
    b.match_property_type,
    b.building_gfa_sqft,
    b.building_eui_kbtu_sqft,
    b.building_gfa_sqft is not null as has_building_data,
    b.portfolio_gfa_sqft,
    b.portfolio_ghg_kgco2e,
    b.portfolio_ghg_intensity_kgco2e_sqft,
    b.portfolio_standard_kgco2e_sqft,
    c.comstock_type,
    a.models as comstock_models,
    a.represented_buildings as comstock_represented_buildings,
    a.eui_kbtu_sqft as comstock_eui_kbtu_sqft,
    a.ghg_intensity_kgco2e_sqft as comstock_ghg_intensity_kgco2e_sqft,
    a.electricity_share as comstock_electricity_share,
    a.natural_gas_share as comstock_natural_gas_share,
    a.oil_propane_share as comstock_oil_propane_share,
    a.district_heating_share as comstock_district_heating_share,
    -- above 1: the BERDO limit is looser than this ComStock archetype's typical emissions
    b.portfolio_standard_kgco2e_sqft / a.ghg_intensity_kgco2e_sqft as standard_vs_comstock,
    -- above 1: the school emits more per sq ft than this ComStock archetype (null until reported)
    b.portfolio_ghg_intensity_kgco2e_sqft / a.ghg_intensity_kgco2e_sqft as ghg_intensity_vs_comstock
from {{ ref('int_school_buildings') }} as b
inner join {{ ref('berdo_comstock_type_crosswalk') }} as c
    on b.match_property_type = c.berdo_type
inner join {{ ref('int_comstock_archetypes') }} as a using (comstock_type)
