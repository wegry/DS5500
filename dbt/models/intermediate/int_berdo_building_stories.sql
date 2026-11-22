-- Estimated stories for each BERDO building, from its parcel's building footprint and roof
-- height (int_boston_parcel_buildings). Neither BERDO nor the assessor (commercial parcels)
-- reports floor counts. Two estimates:
--   stories_from_gfa:    BERDO GFA / footprint. Consistent with how ComStock's geometry
--                        relates sqft to stories, but wrong when the parcel's footprint is a
--                        fragment of the building or includes other buildings; only made
--                        when the building is the parcel's sole BERDO building.
--   stories_from_height: mean roof height / var("floor_to_floor_ft"). Robust to footprint
--                        errors, but the heights are from 2010.
-- stories uses the GFA estimate when the two agree within a factor of 1.6, else the height
-- estimate. A GFA estimate with no height to check it (the footprint postdates the 2010
-- LiDAR) is kept only up to var("max_stories"); above that the parcel holds only a fragment
-- of the building (BERDO 104376: 110,005 sq ft over a 175 sq ft footprint = 630 stories),
-- so the building gets no estimate. Of the 252 matched offices with both, 218 agree (log correlation 0.89, median
-- GFA / height ratio 1.10).
-- Grain: one row per BERDO building on a parcel with a building footprint.
with buildings as (
    select
        berdo_id,
        tax_parcel_id,
        gfa_sqft,
        count(*) over (partition by tax_parcel_id) as parcel_berdo_buildings
    from {{ ref('stg_berdo__buildings') }}
    where berdo_id is not null and tax_parcel_id is not null
),

estimates as (
    select
        b.*,
        g.footprint_sqft,
        g.mean_height_ft,
        g.max_height_ft,
        g.exterior_perimeter_ft,
        case when b.parcel_berdo_buildings = 1 and b.gfa_sqft > 0
            then b.gfa_sqft / g.footprint_sqft end as stories_from_gfa,
        g.mean_height_ft / {{ var("floor_to_floor_ft") }} as stories_from_height
    from buildings as b
    inner join {{ ref('int_boston_parcel_buildings') }} as g
        on g.parcel_id = b.tax_parcel_id
),

chosen as (
    select
        *,
        case
            when stories_from_gfa / stories_from_height between 1 / 1.6 and 1.6
                then 'gfa_over_footprint'
            when stories_from_height > 0 then 'roof_height'
            -- no measured height to check it against
            when stories_from_gfa > 0 and stories_from_gfa <= {{ var("max_stories") }}
                then 'gfa_over_footprint_unchecked'
        end as stories_source
    from estimates
)

select
    *,
    -- floored at one story
    greatest(1, case stories_source
        when 'roof_height' then stories_from_height
        else stories_from_gfa
    end) as stories
from chosen
where stories_source is not null
