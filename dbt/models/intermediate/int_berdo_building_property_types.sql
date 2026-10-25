-- Every property type a BERDO building reports, with its floor area. Grain: building x type.
-- Only buildings that disclose the type list appear (about half of those with a BERDO ID).
-- Type names can contain parentheses ("Personal Services (Health/Beauty, Dry Cleaning, etc)"),
-- so each entry is matched up to its trailing "(area)". One area is "N/A", hence try_cast.
-- Disclosed GFA includes parking for some buildings and not others, so shares are taken
-- over the listed non-parking area, as Portfolio Manager leaves parking out of building GFA.
{%- set entry = "'(.+?) \\(([^()]*)\\)(?:,|$)'" %}
with entries as (
    select
        berdo_id,
        property_type as largest_property_type,
        unnest(regexp_extract_all(all_property_types, {{ entry }}, 1)) as property_type,
        unnest(regexp_extract_all(all_property_types, {{ entry }}, 2)) as gfa_text
    from {{ ref('stg_berdo__buildings') }}
    where berdo_id is not null
      and all_property_types is not null
),

uses as (
    select
        berdo_id,
        largest_property_type,
        -- same normalization as stg_berdo__buildings.property_type
        regexp_replace(property_type, '\s*/\s*', '/') as property_type,
        try_cast(gfa_text as double) as gfa_sqft
    from entries
)

select
    berdo_id || '-' || property_type as building_property_type_key,
    berdo_id,
    property_type,
    gfa_sqft,
    property_type = largest_property_type as is_largest_property_type,
    property_type = 'Parking' as is_parking,
    case
        when property_type <> 'Parking'
            then gfa_sqft / nullif(
                sum(gfa_sqft) filter (where property_type <> 'Parking')
                    over (partition by berdo_id),
                0
            )
    end as non_parking_gfa_share
from uses
