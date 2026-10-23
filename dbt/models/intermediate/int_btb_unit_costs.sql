-- Retrofit installed cost per unit of the ComStock quantity each BTB technology is costed
-- on: $/sq ft for envelope, $/ton for heat pumps, $/W for LED fixtures. BTB's typical cost
-- covers typical_unit_multiplier units where it states a unit (12 sq ft of window, 70 tons
-- of hydronic heat pump); otherwise it is one product of the typical size: an RTU of
-- metric_1_typical tons, or an LED fixture of metric_1_typical lumens at metric_2_typical
-- lm/W. Costs scale linearly with quantity, so multi-unit and size effects are ignored.
with technologies as (
    select
        *,
        case
            when typical_unit_abbreviation = 'ft2' then 'sqft'
            when typical_unit_abbreviation = 'ton' or metric_1_unit = 'Tons' then 'ton'
            when metric_1_unit = 'Lumens' and metric_2_unit = 'lm/W' then 'W'
        end as cost_unit,
        case
            when typical_unit_abbreviation in ('ft2', 'ton') then typical_unit_multiplier
            when metric_1_unit = 'Tons' then metric_1_typical
            when metric_1_unit = 'Lumens' and metric_2_unit = 'lm/W'
                then metric_1_typical / metric_2_typical
        end as typical_quantity
    from {{ ref('stg_btb__technologies') }}
    where btb_measure_id in (select btb_measure_id from {{ ref('comstock_package_components') }})
)

select
    btb_measure_id,
    display_name,
    cost_unit,
    typical_quantity,
    {% for c in ["low", "mid", "high"] -%}
    retrofit_installed_cost_{{ c }}_usd / typical_quantity as unit_cost_{{ c }}_usd,
    {% endfor -%}
    lifetime_years
from technologies
