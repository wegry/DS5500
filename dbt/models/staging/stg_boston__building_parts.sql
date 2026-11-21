-- City of Boston building roof outlines (var "boston_buildings_url"): one polygon per roof
-- section, with its 2010 LiDAR height in feet. Keeps structures typed as buildings (drops
-- outbuildings, walkways, ruins, foundations, construction sites and mobile homes) and
-- projects to Massachusetts State Plane (EPSG:26986, meters) for areas and perimeters.
-- Ephemeral: the geometry is only needed to place each part on a parcel
-- (int_boston_parcel_buildings), so it is not stored.
{{ config(materialized='ephemeral') }}

select
    OBJECTID as building_part_id,
    try_cast(BLDG_HGT_2010 as double) as height_ft,
    st_transform(geom, 'EPSG:4326', 'EPSG:26986', always_xy := true) as geom_m
from st_read('/vsizip//vsicurl/{{ var("boston_buildings_url") }}/Boston_Buildings_with_Roof_Breaks.geojson')
-- 'BUIDLING' is a typo in the source
where coalesce(upper(trim(IEL_TYPE)), 'BLDG') in ('BLDG', 'BUIDLING', '')
