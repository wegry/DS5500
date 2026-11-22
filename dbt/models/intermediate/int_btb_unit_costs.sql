-- Retrofit installed cost per unit of the ComStock quantity each BTB technology is costed
-- on: $/sq ft for envelope, $/ton for heat pumps, $/W for LED fixtures. BTB's typical cost
-- covers typical_unit_multiplier units where it states a unit (12 sq ft of window, 70 tons
-- of hydronic heat pump, 11,000 CFM of energy recovery wheel); otherwise it is one product
-- of the typical size: an RTU or ground-source heat pump of metric_1_typical tons, or an LED
-- fixture of metric_1_typical lumens at metric_2_typical lm/W. Costs scale linearly with
-- quantity, so multi-unit and size effects are ignored. Costs BTB does not cover (ground
-- loop, economizer, PV) are appended from the imputed_component_costs seed. Also costed: the
-- like-for-like equipment of existing_hvac_like_for_like (a gas boiler is one product of
-- metric_1_typical Btu/h).
-- All costs are converted to var("dollar_year") dollars: BTB's from var("btb_dollar_year"),
-- the seed's from each row's dollar_year (to_dollar_year macro). Where a source gives no
-- price year, the seed uses its publication year.
with technologies as (
    select
        *,
        case
            when typical_unit_abbreviation = 'ft2' then 'sqft'
            when typical_unit_abbreviation = 'CFM' then 'CFM'
            when typical_unit_abbreviation = 'ton' or metric_1_unit = 'Tons' then 'ton'
            when metric_1_unit = 'Lumens' and metric_2_unit = 'lm/W' then 'W'
            when metric_1_unit = 'Btu/h' then 'Btu/h'
        end as cost_unit,
        case
            when typical_unit_abbreviation in ('ft2', 'ton', 'CFM') then typical_unit_multiplier
            when metric_1_unit in ('Tons', 'Btu/h') then metric_1_typical
            when metric_1_unit = 'Lumens' and metric_2_unit = 'lm/W'
                then metric_1_typical / metric_2_typical
        end as typical_quantity
    from {{ ref('stg_btb__technologies') }}
    where btb_measure_id in (select btb_measure_id from {{ ref('comstock_package_components') }})
       or btb_measure_id in (select btb_measure_id from {{ ref('existing_hvac_like_for_like') }})
)

select
    btb_measure_id,
    display_name,
    cost_unit,
    typical_quantity,
    {% for c in ["low", "mid", "high"] -%}
    retrofit_installed_cost_{{ c }}_usd / typical_quantity
        * {{ to_dollar_year(var("btb_dollar_year")) }} as unit_cost_{{ c }}_usd,
    {% endfor -%}
    lifetime_years
from technologies

union all
select
    i.btb_measure_id, i.display_name, i.cost_unit, i.typical_quantity,
    {% for c in ["low", "mid", "high"] -%}
    i.unit_cost_{{ c }}_usd * {{ to_dollar_year("i.dollar_year") }} as unit_cost_{{ c }}_usd,
    {% endfor -%}
    i.lifetime_years
from {{ ref('imputed_component_costs') }} as i
