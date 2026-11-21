-- Each matching configuration against unweighted matching without the district rule, at
-- k = 10, 15 and 20: paired bootstrap over held-out models of each model's mean error
-- across the upgrades, for all models and for those using district energy (negative =
-- better than unweighted). Writes analysis_outputs/weighted_district/bootstrap.csv.
-- Grain: k x configuration x subset.
{{ config(post_hook="{{ export_csv('weighted_district/bootstrap.csv', 'k, config_order, models', exclude='config_order') }}") }}

with per_model as (
    select
        held_out_id,
        any_value(held_out_uses_district) as uses_district,
        k::int as k,
        weighting,
        district_rule,
        avg(err_pp) as err_pp
    from {{ ref('analysis_loo_errors') }}
    where k in ('10', '15', '20')
    group by held_out_id, k, weighting, district_rule
),

diffs as (
    select
        c.k,
        c.weighting || case when c.district_rule then ' + district rule' else '' end as config,
        s.models,
        c.held_out_id as unit_id,
        c.err_pp - b.err_pp as diff
    from per_model as c
    inner join per_model as b
        on b.held_out_id = c.held_out_id and b.k = c.k
        and b.weighting = 'unweighted' and not b.district_rule
    cross join (values ('all'), ('district')) as s(models)
    where not (c.weighting = 'unweighted' and not c.district_rule)
      and (s.models = 'all' or c.uses_district)
),

boot as (
    {{ paired_bootstrap('diffs', ['k', 'config', 'models']) }}
)

select
    k,
    config,
    models,
    n,
    round(mean_diff, 4) as diff_vs_unweighted_pp,
    round(ci95_low, 4) as ci95_low_pp,
    round(ci95_high, 4) as ci95_high_pp,
    list_position(
        ['inverse_distance', 'unweighted + district rule', 'inverse_distance + district rule'],
        config
    ) as config_order
from boot
