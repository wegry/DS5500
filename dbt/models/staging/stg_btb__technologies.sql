-- NLR 2024 Buildings Technology Baseline, commercial: one row per technology for the
-- var("btb_year") / var("btb_scenario") projection. Dollar columns are text like "$15,447".
{%- set costs = {"low": "Low", "mid": "Mid", "high": "High"} %}
with raw as (
    select *
    from read_csv('{{ var("btb_csv") }}', header = true, all_varchar = true)
)

select
    try_cast("Technology/Measure ID" as integer) as btb_measure_id,
    "End Use Category" as end_use_category,
    "Component" as component,
    "Technology/Measure" as technology,
    "Display Name" as display_name,
    "Regression Output Units" as regression_output_units,
    "Regression metric 1 - Metric" as metric_1,
    "Regression metric 1 - Unit" as metric_1_unit,
    try_cast("Regression metric 1 - Typical" as double) as metric_1_typical,
    "Regression metric 2 - Metric" as metric_2,
    "Regression metric 2 - Unit" as metric_2_unit,
    try_cast("Regression metric 2 - Typical" as double) as metric_2_typical,
    -- the typical installed cost is for this many units (e.g. 12 sq ft of window)
    try_cast("Typical unit multiplier" as double) as typical_unit_multiplier,
    "Typical unit multiplier units abbreviation" as typical_unit_abbreviation,
    {% for col, label in costs.items() -%}
    try_cast(regexp_replace("Typical Retrofit Installed Cost ($2023) - {{ label }}", '[$,]', '', 'g') as double)
        as retrofit_installed_cost_{{ col }}_usd,
    {% endfor -%}
    try_cast("Lifetime (Years)" as double) as lifetime_years,
    "Notes" as notes
from raw
where try_cast("Year" as integer) = {{ var("btb_year") }}
  and "Scenario" = '{{ var("btb_scenario") }}'
