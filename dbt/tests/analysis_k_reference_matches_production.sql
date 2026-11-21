-- The k-sensitivity twin of the retrofit chain at the project's k must reproduce
-- berdo_decisions; rows returned are buildings where it does not.
select coalesce(a.berdo_id, d.berdo_id) as berdo_id
from (select * from {{ ref('analysis_k_decisions') }} where k = {{ var("match_k") }}) as a
full join {{ ref('berdo_decisions') }} as d using (berdo_id)
where a.recommended_upgrade_id is distinct from d.recommended_upgrade_id
   or a.meets_standard is distinct from d.meets_standard
   or not abs(a.total_cost_mid_usd - d.total_cost_mid_usd) <= 0.01
