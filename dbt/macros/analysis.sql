{#- Helpers for the analysis models (models/analysis). -#}

{#- A post-hook that writes the model to a CSV, leaving out the `exclude` columns (e.g. a
    sort key). `file` is relative to var("analysis_outputs_dir") unless `dir` is given. -#}
{% macro export_csv(file, order_by, dir=none, exclude=none) -%}
copy (
    select *{% if exclude %} exclude ({{ exclude }}){% endif %}
    from {{ this }} order by {{ order_by }}
)
to '{{ dir or var("analysis_outputs_dir") }}/{{ file }}' (header)
{%- endmacro %}


{#- Paired cluster bootstrap of mean differences. `diffs` has one row per unit (unit_id)
    and comparison (the `group_cols`) with its `diff`. Each of var("bootstrap_draws")
    resamples draws n units with replacement, picked by a seeded hash so reruns agree;
    the interval is the resampled means' 2.5th and 97.5th percentiles. -#}
{% macro paired_bootstrap(diffs, group_cols) %}
{%- set g = group_cols | join(", ") %}
with units as (
    select
        {{ g }},
        diff,
        row_number() over (partition by {{ g }} order by unit_id) - 1 as unit_index,
        count(*) over (partition by {{ g }}) as n
    from {{ diffs }}
),

comparisons as (
    select {{ g }}, any_value(n) as n, avg(diff) as mean_diff,
        avg((diff < 0)::int) as share_negative
    from units
    group by {{ g }}
),

picks as (
    select
        {{ g }},
        draw,
        hash({{ var("bootstrap_seed") }}, {{ g }}, draw, slot) % n as unit_index
    from (
        select {{ g }}, n, draw, unnest(range(n)) as slot
        from comparisons
        cross join range({{ var("bootstrap_draws") }}) as draws(draw)
    )
),

resampled as (
    select {{ g }}, p.draw, avg(u.diff) as mean_diff
    from picks as p
    inner join units as u using ({{ g }}, unit_index)
    group by {{ g }}, p.draw
)

select
    c.*,
    quantile_disc(r.mean_diff, 0.025) as ci95_low,
    quantile_disc(r.mean_diff, 0.975) as ci95_high
from comparisons as c
inner join resampled as r using ({{ g }})
group by all
{% endmacro %}
