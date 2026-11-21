-- How the 20-year picks for the over-limit offices change with k, against the reference
-- k = var("match_k"): the cheapest option, and the cheapest option that meets the standard
-- for offices that have one at both k and the reference. Writes
-- analysis_outputs/k_sensitivity/data/global_k_summary.csv.
-- Grain: k x perspective.
{{ config(post_hook="{{ export_csv('k_sensitivity/data/global_k_summary.csv', 'perspective, k') }}") }}

select
    a.perspective,
    a.k,
    count(*) as offices,
    count(*) filter (where a.cheapest_compliant_upgrade_id is not null) as has_compliant_option,
    count(*) filter (where a.cheapest_upgrade_id <> 0) as retrofit_cheapest,
    count(*) filter (where a.cheapest_meets_standard) as cheapest_meets_standard,
    count(*) filter (where a.cheapest_upgrade_id <> r.cheapest_upgrade_id) as cheapest_changed_vs_ref,
    count(*) filter (
        where a.cheapest_compliant_upgrade_id is not null
          and r.cheapest_compliant_upgrade_id is not null
    ) as compliant_compared,
    count(*) filter (
        where a.cheapest_compliant_upgrade_id <> r.cheapest_compliant_upgrade_id
    ) as cheapest_compliant_changed_vs_ref
from {{ ref('analysis_k_global_choices') }} as a
inner join {{ ref('analysis_k_global_choices') }} as r
    on r.perspective = a.perspective and r.berdo_id = a.berdo_id and r.k = {{ var("match_k") }}
group by a.perspective, a.k
