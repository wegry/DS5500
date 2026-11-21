-- Every building has exactly k matched models at each k.
select k, berdo_id, count(*) as neighbors
from {{ ref('analysis_k_matches') }}
group by k, berdo_id
having count(*) <> k
