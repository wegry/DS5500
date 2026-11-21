-- Every held-out model has at least floor(sqrt(n)) neighbors overall and among those that
-- agree on district energy, so each k in the leave-one-out sweep pools exactly k models.
with n as (
    select floor(sqrt(count(distinct held_out_id))) as k_max
    from {{ ref('analysis_loo_neighbors') }}
)
select held_out_id
from {{ ref('analysis_loo_neighbors') }}
group by held_out_id
having max(rank_all) < (select k_max from n) or max(rank_rule) < (select k_max from n)
