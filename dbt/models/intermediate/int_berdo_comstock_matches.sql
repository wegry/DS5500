-- The var("match_k") nearest ComStock baseline models for each BERDO building, among the
-- ComStock types its property type maps to. Distance: log size gap + log EUI gap + half
-- the L1 gap between fuel shares + log stories gap (the terms are kept for match-quality
-- checks; see macros/matching.sql, which the leave-one-out validation shares). A building
-- without a stories estimate (int_berdo_building_stories) gets a stories gap of 0 for every
-- candidate, so its ranking rests on the other three terms.
-- var("match_w_size"/"match_w_eui"/"match_w_fuel"/"match_w_stories") weight the terms (1
-- each by default), and var("match_district_rule") restricts candidates to models whose
-- district-energy use (any vs none) agrees with the building's.
-- var("match_weighting") sets how much each neighbor counts when downstream models pool
-- them: equally (unweighted) or by 1 / (distance + 1e-6) (inverse_distance).
{% set weighting = var("match_weighting", "unweighted") %}
with models as (
    {{ comstock_match_features() }}
),

candidates as (
    select
        b.berdo_id,
        m.comstock_id,
        m.comstock_type,
        {{ match_gaps('b', 'm') }}
    from {{ ref('int_berdo_match_buildings') }} as b
    inner join {{ ref('berdo_comstock_type_crosswalk') }} as cw
        on b.property_type = cw.berdo_type
    inner join models as m
        on cw.comstock_type = m.comstock_type
    {%- if var("match_district_rule", false) %}
    where (b.district_share > 0) = m.uses_district
    {%- endif %}
),

weighted as (
    select
        *,
        {{ match_distance() }} as distance
    from candidates
)

select
    berdo_id || '-' || comstock_id as match_key,
    *,
    {{ match_weight(weighting) }} as match_weight,
    -- the matching settings, so Python checks can mirror this build
    '{{ weighting }}' as match_weighting,
    {{ var("match_district_rule", false) }} as match_district_rule,
    {{ var("match_w_stories", 1) }} as match_w_stories,
    row_number() over (partition by berdo_id order by distance, comstock_id) as match_rank
from weighted
qualify match_rank <= {{ var("match_k") }}
