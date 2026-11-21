-- Is the project's k better than its baselines? Paired bootstrap over held-out models of
-- each model's mean error across the upgrades: var("match_k") minus k = all, type and 1
-- (negative = the project's k is better). Writes analysis_outputs/loo_tests.csv.
-- Grain: comparison.
{{ config(post_hook="{{ export_csv('loo_tests.csv', 'comparison_order', exclude='comparison_order') }}") }}

with per_model as (
    select held_out_id, k, avg(err_pp) as err_pp
    from {{ ref('analysis_loo_errors') }}
    where is_project_config and k in ('1', '{{ var("match_k") }}', 'type', 'all')
    group by all
),

diffs as (
    select
        '{{ var("match_k") }} minus ' || o.k as comparison,
        r.held_out_id as unit_id,
        r.err_pp - o.err_pp as diff
    from per_model as r
    inner join per_model as o using (held_out_id)
    where r.k = '{{ var("match_k") }}' and o.k in ('all', 'type', '1')
),

boot as (
    {{ paired_bootstrap('diffs', ['comparison']) }}
)

select
    comparison,
    round(mean_diff, 2) as mean_diff_pp,
    round(ci95_low, 2) as ci95_low_pp,
    round(ci95_high, 2) as ci95_high_pp,
    round(share_negative, 3) as share_models_reference_better,
    list_position(['all', 'type', '1'], split_part(comparison, ' minus ', 2)) as comparison_order
from boot
