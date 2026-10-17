-- ComStock building types summarized for Suffolk County. Intensities and fuel shares are
-- floor-area weighted using the ComStock sampling weight.
select
    comstock_type,
    count(*) as models,
    sum(weight) as represented_buildings,
    sum(weight * gfa_sqft) as represented_gfa_sqft,
    sum(weight * eui_kbtu_sqft * gfa_sqft) / sum(weight * gfa_sqft) as eui_kbtu_sqft,
    sum(weight * ghg_kgco2e) / sum(weight * gfa_sqft) as ghg_intensity_kgco2e_sqft,
    sum(weight * electricity_kbtu) / sum(weight * eui_kbtu_sqft * gfa_sqft) as electricity_share,
    sum(weight * natural_gas_kbtu) / sum(weight * eui_kbtu_sqft * gfa_sqft) as natural_gas_share,
    sum(weight * oil_propane_kbtu) / sum(weight * eui_kbtu_sqft * gfa_sqft) as oil_propane_share,
    sum(weight * district_heating_kbtu) / sum(weight * eui_kbtu_sqft * gfa_sqft) as district_heating_share
from {{ ref('stg_comstock__baseline') }}
group by comstock_type
