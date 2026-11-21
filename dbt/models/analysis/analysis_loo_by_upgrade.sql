-- Leave-one-out error by upgrade for the project's configuration at k = 1, var("match_k"),
-- 'type' and 'all'. Writes analysis_outputs/loo_by_upgrade.csv.
-- Grain: k x upgrade.
{{ config(post_hook="{{ export_csv('loo_by_upgrade.csv', 'upgrade_id, k') }}") }}

select
    k,
    upgrade_id,
    round(avg(actual_reduction_pct), 1) as mean_actual_reduction_pct,
    round(avg(err_pp), 2) as mae_pp
from {{ ref('analysis_loo_errors') }}
where is_project_config and k in ('1', '{{ var("match_k") }}', 'type', 'all')
group by all
