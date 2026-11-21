-- Neighbor-count sensitivity: the project's matches (int_berdo_comstock_matches) truncated
-- to each k = 1 .. var("match_k"), so the analysis_k_* twins of the retrofit chain can rerun
-- the five-year decision at every k in one build (macros/retrofit_chain.sql).
-- Grain: k x BERDO building x matched model.
select ks.k, m.*
from {{ ref('int_berdo_comstock_matches') }} as m
inner join range(1, {{ var("match_k") }} + 1) as ks(k) on m.match_rank <= ks.k
