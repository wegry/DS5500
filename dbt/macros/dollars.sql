{#- Multiplier that converts from_year dollars to var("dollar_year") dollars with the GDP
    price deflator (gdp_price_deflator seed). from_year is a SQL expression, so it can be a
    column (e.g. a seed's dollar_year) or a literal. -#}
{% macro to_dollar_year(from_year) -%}
(
    (select gdp_price_index_2017 from {{ ref('gdp_price_deflator') }}
     where year = {{ var("dollar_year") }})
    / (select gdp_price_index_2017 from {{ ref('gdp_price_deflator') }}
       where year = {{ from_year }})
)
{%- endmacro %}
