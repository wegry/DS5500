-- Offices whose five-year recommendation at k differs from the one at var("match_k") (the
-- reference). Writes analysis_outputs/k_sensitivity/data/full_k_changes.csv.
-- Grain: k x changed office.
{{ config(post_hook="{{ export_csv('k_sensitivity/data/full_k_changes.csv', 'k, berdo_id') }}") }}

select
    a.k,
    a.berdo_id,
    a.recommended_upgrade_id as upgrade_at_k,
    r.recommended_upgrade_id as upgrade_at_ref,
    a.total_cost_mid_usd as cost_at_k_usd,
    r.total_cost_mid_usd as cost_at_ref_usd,
    a.meets_standard as meets_standard_at_k,
    r.meets_standard as meets_standard_at_ref
from {{ ref('analysis_k_cohort_decisions') }} as a
inner join {{ ref('analysis_k_cohort_decisions') }} as r
    on r.berdo_id = a.berdo_id and r.k = {{ var("match_k") }}
where a.recommended_upgrade_id <> r.recommended_upgrade_id
