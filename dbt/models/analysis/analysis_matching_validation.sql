-- Leave-one-out error for every matching configuration, {unweighted, inverse_distance} x
-- {no district rule, district rule}, at k = 1 .. floor(sqrt(n)): the evidence for the
-- project's match_k, match_weighting and match_district_rule. Writes
-- analysis_outputs/weighted_district/summary.csv and Report 2's matching_validation.csv.
-- Grain: k x method x rule.
{{ config(post_hook=[
    "{{ export_csv('weighted_district/summary.csv', 'k, rule, method') }}",
    "{{ export_csv('matching_validation.csv', 'k, rule, method', dir=var('report_data_dir')) }}",
]) }}

select
    k::int as k,
    weighting as method,
    district_rule as rule,
    count(distinct held_out_id) as held_out_models,
    count(*) as predictions,
    round(avg(err_pp), 3) as mae_pp,
    round(median(err_pp), 3) as median_ae_pp,
    round(quantile_cont(err_pp, 0.9), 3) as p90_ae_pp,
    round(avg(err_pp) filter (where held_out_uses_district), 3) as mae_pp_district_models,
    round(avg(err_pp) filter (where not held_out_uses_district), 3) as mae_pp_other_models
from {{ ref('analysis_loo_errors') }}
where k not in ('all', 'type')
group by all
