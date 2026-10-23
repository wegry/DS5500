-- How closely each matched BERDO building's var("match_k") ComStock models resemble it.
-- Gaps are the terms of the match distance: |ln size ratio|, |ln EUI ratio|, and half the
-- L1 gap in fuel shares (0 = identical mix, 1 = no fuel in common). exp(gap) - 1 reads as
-- a relative difference, e.g. a size_gap of 0.2 is about 22% larger or smaller.
-- Grain: one row per matched BERDO building.
select
    b.berdo_id,
    b.owner_name,
    b.building_address,
    b.property_type,
    b.gfa_sqft,
    b.eui_kwh_sqft,
    count(*) as matched_models,
    min(m.distance) as nearest_distance,
    avg(m.distance) as mean_distance,
    max(m.distance) as max_distance,
    avg(m.size_gap) as mean_size_gap,
    avg(m.eui_gap) as mean_eui_gap,
    avg(m.fuel_share_gap) as mean_fuel_share_gap,
    count(distinct m.comstock_type) as comstock_types,
    mode(m.comstock_type) as most_common_comstock_type
from {{ ref('int_berdo_match_buildings') }} as b
inner join {{ ref('int_berdo_comstock_matches') }} as m using (berdo_id)
group by all
