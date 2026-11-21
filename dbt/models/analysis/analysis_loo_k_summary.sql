-- Leave-one-out error by neighbor count for the project's matching configuration, with the
-- 'all' and same-type ('type') baselines. Writes analysis_outputs/loo_k_summary.csv.
-- Grain: k.
{{ config(post_hook="{{ export_csv('loo_k_summary.csv', 'try_cast(k as int) nulls last, k') }}") }}

select
    k,
    count(distinct held_out_id) as held_out_models,
    count(*) as predictions,
    round(avg(err_pp), 2) as mae_pp,
    round(median(err_pp), 2) as median_ae_pp,
    round(quantile_cont(err_pp, 0.9), 2) as p90_ae_pp,
    round(avg(err_kg_sqft), 3) as mae_kg_sqft
from {{ ref('analysis_loo_errors') }}
where is_project_config
group by k
