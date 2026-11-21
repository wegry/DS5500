-- Building footprint and height per Boston parcel. Each roof section is assigned to the
-- parcel containing a point on its surface, so a building that straddles a lot line
-- counts toward whichever parcel holds each of its sections.
-- Grain: one row per parcel with at least one building section.
{{ config(materialized='table') }}

with assigned as (
    select
        p.parcel_id,
        b.height_ft,
        st_area(b.geom_m) * 10.7639 as area_sqft,
        b.geom_m
    from {{ ref('stg_boston__building_parts') }} as b
    inner join {{ ref('stg_boston__parcels') }} as p
        on st_contains(p.geom_m, st_pointonsurface(b.geom_m))
)

select
    parcel_id,
    count(*) as building_parts,
    sum(area_sqft) as footprint_sqft,
    -- footprint-weighted, over sections with a measured height
    sum(height_ft * area_sqft) filter (where height_ft > 0)
        / nullif(sum(area_sqft) filter (where height_ft > 0), 0) as mean_height_ft,
    max(height_ft) as max_height_ft,
    -- outline of the merged sections, i.e. exterior wall length (m -> ft)
    st_perimeter(st_union_agg(st_makevalid(geom_m))) * 3.28084 as exterior_perimeter_ft
from assigned
group by parcel_id
