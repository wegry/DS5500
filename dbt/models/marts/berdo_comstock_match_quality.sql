
-- Evaluate BERDO-ComStock matching quality.
-- One row per BERDO office building.

select
    berdo_id,
    count(*) as number_of_matches,

    -- Closest ComStock match
    max(distance) filter (where match_rank = 1
    ) as nearest_distance,
    max(size_gap) filter (where match_rank = 1
    ) as nearest_size_gap,
    max(eui_gap) filter (where match_rank = 1
    ) as nearest_eui_gap,
    max(fuel_share_gap) filter (where match_rank = 1
    ) as nearest_fuel_gap,

    -- Quality across all selected matches
    avg(distance) as average_distance,
    max(distance) filter (where match_rank = 10
    ) as tenth_match_distance,

    -- Exploratory quality indicators
    case
        when max(distance) filter (where match_rank = 1
        ) > 0.5
        then true
        else false
    end as elevated_distance_flag,

    case
        when max(distance) filter (where match_rank = 1
        ) > 1.0
        then true
        else false
    end as extreme_distance_flag

from {{ ref('int_berdo_comstock_matches') }}
group by berdo_id
