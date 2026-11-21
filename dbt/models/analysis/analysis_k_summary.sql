-- Five-year outcomes for the over-limit offices at each k, and how many differ from the
-- reference k = var("match_k"). Writes analysis_outputs/k_sensitivity/data/full_k_summary.csv.
-- Grain: k.
{{ config(post_hook="{{ export_csv('k_sensitivity/data/full_k_summary.csv', 'k') }}") }}

with compliant as (
    select k, count(distinct berdo_id) as has_compliant_option
    from {{ ref('analysis_k_cohort_options') }}
    where meets_standard
    group by k
)

select
    a.k,
    count(*) as offices,
    any_value(c.has_compliant_option) as has_compliant_option,
    count(*) filter (where a.recommended_upgrade_id = 0) as no_upgrade_selected,
    count(*) filter (where a.recommended_upgrade_id <> 0) as retrofit_selected,
    count(*) filter (where a.meets_standard) as selected_meets_standard,
    count(*) filter (where a.recommended_upgrade_id <> r.recommended_upgrade_id)
        as different_upgrade_vs_ref,
    count(*) filter (where a.meets_standard <> r.meets_standard) as different_compliance_vs_ref
from {{ ref('analysis_k_cohort_decisions') }} as a
inner join {{ ref('analysis_k_cohort_decisions') }} as r
    on r.berdo_id = a.berdo_id and r.k = {{ var("match_k") }}
left join compliant as c on c.k = a.k
group by a.k
