-- The k-sensitivity twin of the 20-year global cost at the project's k must reproduce
-- berdo_global_cost (projected scenario, mid prices); rows returned are options where it does not.
select coalesce(a.global_cost_key, p.global_cost_key) as global_cost_key
from (
    select * from {{ ref('analysis_k_global_cost') }} where k = {{ var("match_k") }}
) as a
full join (
    select * from {{ ref('berdo_global_cost') }}
    where scenario = 'projected' and energy_price = 'mid'
) as p
    on p.berdo_id = a.berdo_id and p.upgrade_id = a.upgrade_id and p.perspective = a.perspective
where a.berdo_id is null or p.berdo_id is null
   or not abs(a.global_cost_mid_usd - p.global_cost_mid_usd) <= 0.01
   or a.cost_rank_mid <> p.cost_rank_mid
   or a.meets_standard_at_start is distinct from p.meets_standard_at_start
