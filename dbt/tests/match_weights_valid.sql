-- All matches must have positive finite weights; unweighted matches have weight 1.
select match_key, match_weight
from {{ ref('int_berdo_comstock_matches') }}
where match_weight is null or not isfinite(match_weight) or match_weight <= 0
