-- Leave-one-out validation of the matching. Real buildings have no observed post-retrofit
-- outcome, but ComStock's simulated offices do, so each office model in turn plays a BERDO
-- building: it is hidden, matched to the other models with the BERDO match distance
-- (macros/matching.sql), and its upgrade emissions are predicted from theirs
-- (analysis_loo_predictions). This measures how well retrofit effects transfer between
-- simulated buildings, not real-world accuracy; held-out models also have their exact
-- story counts, where BERDO buildings have estimates or none.
-- Ranks every other model by distance, overall (rank_all) and among models that agree on
-- using district energy (rank_rule, the district rule).
-- Grain: held-out model x other model, over the ComStock types the BERDO cohort maps to.
with models as (
    select *
    from ({{ comstock_match_features() }})
    where comstock_type in (
        select cw.comstock_type
        from {{ ref('berdo_comstock_type_crosswalk') }} as cw
        inner join {{ ref('int_berdo_match_buildings') }} as b on cw.berdo_type = b.property_type
    )
      and gfa_sqft > 0 and eui_kwh_sqft > 0 and fuel_total_kwh > 0
),

pairs as (
    select
        h.comstock_id as held_out_id,
        c.comstock_id as neighbor_id,
        h.uses_district = c.uses_district as district_agrees,
        {{ match_gaps('h', 'c') }}
    from models as h
    inner join models as c on h.comstock_id <> c.comstock_id
),

distances as (
    select *, {{ match_distance() }} as distance
    from pairs
)

select
    *,
    row_number() over (partition by held_out_id order by distance, neighbor_id) as rank_all,
    case when district_agrees then row_number() over (
        partition by held_out_id, district_agrees order by distance, neighbor_id
    ) end as rank_rule
from distances
