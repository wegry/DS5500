-- City of Boston parcel polygons (var "boston_parcels_url"), keyed by the assessing PID that
-- BERDO's Tax Parcel ID uses. Rights-of-way and water have no PID and are dropped. A PID can
-- have more than one polygon. Ephemeral, like stg_boston__building_parts.
{{ config(materialized='ephemeral') }}

select
    try_cast(MAP_PAR_ID as bigint) as parcel_id,
    st_transform(geom, 'EPSG:4326', 'EPSG:26986', always_xy := true) as geom_m
from st_read('/vsizip//vsicurl/{{ var("boston_parcels_url") }}/Parcels_2025.geojson')
where try_cast(MAP_PAR_ID as bigint) is not null
