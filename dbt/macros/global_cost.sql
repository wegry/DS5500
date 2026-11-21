{#- The 20-year global cost (berdo_global_cost), as a macro so its analysis_k_* twin can run
    the same SQL over the retrofit chain at every neighbor count k. With by_k the relations
    carry a k column, which every grouping, join and window then includes; without it the
    SQL is the production model's, unchanged. scenario_names and energy_prices restrict the
    energy scenarios and price cases (all of them when none). berdo_global_cost documents
    what each step does. -#}

{% macro berdo_global_cost(options, scenarios, package_costs, existing_hvac, by_k=false,
                           scenario_names=none, energy_prices=none) %}
{%- set k_ = "k, " if by_k else "" %}
{%- set costs = ["low", "mid", "high"] %}
{%- set n = var("global_cost_years") %}
{%- set start = var("decision_period_start") %}
{%- set fuels = ["electricity", "natural_gas", "oil_propane", "district_heating", "district_cooling"] %}
{#- which AEO2026 price series each fuel follows #}
{%- set price_series = {"electricity": "electricity", "district_cooling": "electricity",
    "natural_gas": "natural_gas", "district_heating": "natural_gas", "oil_propane": "distillate"} %}
with perspectives as (
    select * from (values
        ('financial', {{ var("discount_rate_financial") }}),
        ('societal', {{ var("discount_rate_societal") }})
    ) as t (perspective, discount_rate)
),

price_cases as (
    select unnest({{ energy_prices or ['low', 'mid', 'high'] }}) as energy_price
),

scenarios as (
    select scenario, aeo_case, cambium_scenario, berdo_grid_schedule
    from {{ ref('energy_scenarios') }}
    {% if scenario_names %}where scenario in ('{{ scenario_names | join("', '") }}'){% endif %}
),

-- $/kWh by fuel for each price case, one row per case
prices as (
    select
        pr.energy_price,
        {% for f in fuels -%}
        max(case pr.energy_price
            {% for c in costs -%}
            when '{{ c }}' then fp.usd_per_kwh_{{ c }}
            {% endfor -%}
        end) filter (where fp.fuel = '{{ f }}') as {{ f }}_usd_per_kwh{{ "," if not loop.last }}
        {% endfor -%}
    from price_cases as pr
    cross join {{ ref('fuel_prices') }} as fp
    group by pr.energy_price
),

years as (
    select t, {{ start }} + t - 1 as year
    from (select unnest(range(1, {{ n }} + 1)) as t)
),

options as (
    select * from {{ options }}
),

-- BERDO's effective electricity factor: projected grid factor net of the RPS Class I share
berdo_factor as (
    select year, grid_factor_kg_per_mwh * (1 - rps_class_i_pct / 100) as kg_per_mwh
    from {{ ref('berdo_projected_grid_factors') }}
),

-- Cambium's 5-year points, interpolated to every year of the horizon
cambium as (
    select
        c0.cambium_scenario,
        y.year,
        c0.aer_load_co2e_kg_per_mwh
            + (c1.aer_load_co2e_kg_per_mwh - c0.aer_load_co2e_kg_per_mwh)
            * (y.year - c0.year) / (c1.year - c0.year) as kg_per_mwh
    from years as y
    inner join {{ ref('cambium24_isone_aer') }} as c0 on c0.year = y.year - y.year % 5
    inner join {{ ref('cambium24_isone_aer') }} as c1
        on c1.cambium_scenario = c0.cambium_scenario and c1.year = c0.year + 5
),

aeo as (
    select aeo_case, fuel, year, usd2025_per_mmbtu from {{ ref('aeo2026_ne_commercial_prices') }}
),

-- each scenario's indices for each year, relative to 2025 (1 everywhere for 'frozen')
scenario_years as (
    select
        s.scenario,
        y.t,
        y.year,
        case when s.berdo_grid_schedule then bf.kg_per_mwh / bf0.kg_per_mwh else 1 end
            as berdo_electricity_index,
        coalesce(cy.kg_per_mwh / c0.aer_load_co2e_kg_per_mwh, 1) as grid_electricity_index,
        {% for series in ["electricity", "natural_gas", "distillate"] -%}
        coalesce(
            (select a.usd2025_per_mmbtu from aeo as a
             where a.aeo_case = s.aeo_case and a.fuel = '{{ series }}' and a.year = y.year)
            / (select a.usd2025_per_mmbtu from aeo as a
               where a.aeo_case = s.aeo_case and a.fuel = '{{ series }}' and a.year = 2025),
            1
        ) as {{ series }}_price_index{{ "," if not loop.last }}
        {% endfor -%}
    from scenarios as s
    cross join years as y
    inner join berdo_factor as bf on bf.year = y.year
    inner join berdo_factor as bf0 on bf0.year = 2025
    left join cambium as cy on cy.cambium_scenario = s.cambium_scenario and cy.year = y.year
    left join {{ ref('cambium24_isone_aer') }} as c0
        on c0.cambium_scenario = s.cambium_scenario and c0.year = 2025
),

-- present value of $1 of installed cost: installs at 0, L, 2L, ... inside the horizon,
-- less the last install's undepreciated share at the horizon
capital_factors as (
    select
        u.btb_measure_id,
        p.perspective,
        sum(power(1 + p.discount_rate, -ks.k * u.lifetime_years))
            - ((max(ks.k) + 1) * u.lifetime_years - {{ n }}) / u.lifetime_years
            * power(1 + p.discount_rate, -{{ n }}) as capital_factor
    from {{ ref('int_btb_unit_costs') }} as u
    cross join perspectives as p
    -- install k at year k * lifetime; lifetimes are at least a year, so n bounds k
    inner join (select unnest(range(0, {{ n }})) as k) as ks
        on ks.k * u.lifetime_years < {{ n }}
    group by u.btb_measure_id, p.perspective, p.discount_rate, u.lifetime_years
),

capital as (
    select
        {% if by_k %}pc.k,{% endif %}
        pc.berdo_id,
        pc.upgrade_id,
        f.perspective,
        {% for c in costs -%}
        sum(pc.installed_cost_{{ c }}_usd * f.capital_factor) as capital_pv_{{ c }}_usd{{ "," if not loop.last }}
        {% endfor -%}
    from {{ package_costs }} as pc
    inner join capital_factors as f using (btb_measure_id)
    group by {% if by_k %}pc.k, {% endif %}pc.berdo_id, pc.upgrade_id, f.perspective
),

-- the same for existing equipment, first replaced like-for-like after remaining_years
existing_capital_factors as (
    select
        e.btb_measure_id,
        e.remaining_years,
        p.perspective,
        sum(power(1 + p.discount_rate, -(e.remaining_years + ks.k * e.lifetime_years)))
            - ((e.remaining_years + (max(ks.k) + 1) * e.lifetime_years) - {{ n }})
            / e.lifetime_years * power(1 + p.discount_rate, -{{ n }}) as capital_factor
    from (
        select distinct btb_measure_id, remaining_years, lifetime_years
        from {{ existing_hvac }}
    ) as e
    cross join perspectives as p
    inner join (select unnest(range(0, {{ n }})) as k) as ks
        on e.remaining_years + ks.k * e.lifetime_years < {{ n }}
    group by e.btb_measure_id, e.remaining_years, e.lifetime_years, p.perspective, p.discount_rate
),

existing_capital as (
    select
        {% if by_k %}e.k,{% endif %}
        e.berdo_id,
        f.perspective,
        {% for c in costs -%}
        sum(e.replacement_cost_{{ c }}_usd * f.capital_factor) as existing_hvac_pv_{{ c }}_usd
            {{- "," if not loop.last }}
        {% endfor -%}
    from {{ existing_hvac }} as e
    inner join existing_capital_factors as f using (btb_measure_id, remaining_years)
    group by {% if by_k %}e.k, {% endif %}e.berdo_id, f.perspective
),

-- each option's yearly fuel use and emissions at today's grid, split into the electricity
-- part (which a cleaner grid shrinks) and the rest: the building's BERDO use and per-fuel
-- emissions scaled by the upgrade's per-fuel ratios (1 for no retrofit), as in
-- berdo_upgrade_scenarios
fuel_use as (
    select
        {% if by_k %}o.k,{% endif %}
        o.berdo_id,
        o.upgrade_id,
        {% for f in fuels -%}
        bl.{{ f }}_kwh * coalesce(sc.{{ f }}_ratio, 1) as {{ f }}_kwh,
        {% endfor -%}
        bl.electricity_ghg_kgco2e * coalesce(sc.electricity_ratio, 1) as electric_ghg_kgco2e,
        -- the rest as total minus electricity, so no retrofit keeps BERDO's reported total
        -- (its per-fuel figures are rounded and can differ from it by ~0.1 kg)
        coalesce(sc.projected_ghg_kgco2e, bl.ghg_kgco2e)
            - bl.electricity_ghg_kgco2e * coalesce(sc.electricity_ratio, 1) as other_ghg_kgco2e
    from options as o
    inner join {{ ref('int_berdo_match_buildings') }} as bl using (berdo_id)
    left join {{ scenarios }} as sc using ({{ k_ }}berdo_id, upgrade_id)
),

-- each building's limit in each year of the horizon
limits as (
    select co.berdo_id, y.t, y.year, co.standard_kgco2e_sqft * bl.gfa_sqft as limit_kgco2e
    from {{ ref('berdo_upgrade_compliance') }} as co
    inner join {{ ref('int_berdo_match_buildings') }} as bl using (berdo_id)
    inner join years as y on y.year between co.period_start and coalesce(co.period_end, y.year)
    where co.upgrade_id = 0
),

yearly as (
    select
        fu.*,
        sy.*,
        l.limit_kgco2e,
        -- emissions as BERDO counts them (compliance) and as the grid emits them (society)
        fu.electric_ghg_kgco2e * sy.berdo_electricity_index + fu.other_ghg_kgco2e
            as berdo_ghg_kgco2e,
        fu.electric_ghg_kgco2e * sy.grid_electricity_index + fu.other_ghg_kgco2e
            as grid_ghg_kgco2e
    from fuel_use as fu
    inner join limits as l using (berdo_id)
    inner join scenario_years as sy on sy.t = l.t
),

emissions as (
    select
        {% if by_k %}y.k,{% endif %}
        y.berdo_id,
        y.upgrade_id,
        y.scenario,
        p.perspective,
        sum(
            case p.perspective
                when 'financial' then greatest(y.berdo_ghg_kgco2e - y.limit_kgco2e, 0) / 1000
                    * {{ var("acp_usd_per_tco2e") }}
                else y.grid_ghg_kgco2e / 1000 * {{ var("social_cost_usd_per_tco2e") }}
            end
            * power(1 + p.discount_rate, -y.t)
        ) as emissions_cost_pv_usd,
        count(*) filter (where y.berdo_ghg_kgco2e > y.limit_kgco2e) as years_over_limit,
        -- under the standard in the first year (2030), as BERDO counts it
        bool_and(y.berdo_ghg_kgco2e <= y.limit_kgco2e) filter (where y.t = 1)
            as meets_standard_at_start
    from yearly as y
    cross join perspectives as p
    group by {% if by_k %}y.k, {% endif %}y.berdo_id, y.upgrade_id, y.scenario, p.perspective
),

energy as (
    select
        {% if by_k %}y.k,{% endif %}
        y.berdo_id,
        y.upgrade_id,
        y.scenario,
        p.perspective,
        pr.energy_price,
        sum(
            (
                {% for f in fuels -%}
                y.{{ f }}_kwh * pr.{{ f }}_usd_per_kwh * y.{{ price_series[f] }}_price_index{{ " +" if not loop.last }}
                {% endfor -%}
            )
            * power(1 + p.discount_rate, -y.t)
        ) as energy_pv_usd
    from yearly as y
    cross join perspectives as p
    cross join prices as pr
    group by {% if by_k %}y.k, {% endif %}y.berdo_id, y.upgrade_id, y.scenario, p.perspective, pr.energy_price
),

present_values as (
    select
        {% if by_k %}o.k,{% endif %}
        o.berdo_id,
        o.upgrade_id,
        o.upgrade_name,
        e.scenario,
        p.perspective,
        p.discount_rate,
        pr.energy_price,
        e.meets_standard_at_start,
        e.years_over_limit,
        -- present value of $1 a year for n years
        (1 - power(1 + p.discount_rate, -{{ n }})) / p.discount_rate as annuity_factor,
        {% for c in costs -%}
        o.installed_cost_{{ c }}_usd,
        coalesce(k.capital_pv_{{ c }}_usd, 0) as capital_pv_{{ c }}_usd,
        case when o.replaces_hvac then 0 else coalesce(x.existing_hvac_pv_{{ c }}_usd, 0) end
            as existing_hvac_pv_{{ c }}_usd,
        {% endfor -%}
        en.energy_pv_usd,
        e.emissions_cost_pv_usd
    from options as o
    cross join perspectives as p
    cross join price_cases as pr
    inner join emissions as e using ({{ k_ }}berdo_id, upgrade_id, perspective)
    inner join energy as en
        on {% if by_k %}en.k = o.k and {% endif %}en.berdo_id = o.berdo_id and en.upgrade_id = o.upgrade_id and en.scenario = e.scenario
        and en.perspective = p.perspective and en.energy_price = pr.energy_price
    left join capital as k using ({{ k_ }}berdo_id, upgrade_id, perspective)
    left join existing_capital as x
        on {% if by_k %}x.k = o.k and {% endif %}x.berdo_id = o.berdo_id and x.perspective = p.perspective
),

totals as (
    select
        *,
        {% for c in costs -%}
        installed_cost_{{ c }}_usd * {{ var("om_share_per_year") }} * annuity_factor as om_pv_{{ c }}_usd,
        capital_pv_{{ c }}_usd
            + existing_hvac_pv_{{ c }}_usd
            + installed_cost_{{ c }}_usd * {{ var("om_share_per_year") }} * annuity_factor
            + energy_pv_usd
            + emissions_cost_pv_usd as global_cost_{{ c }}_usd{{ "," if not loop.last }}
        {% endfor -%}
    from present_values
)

select
    {% if by_k %}k || '-' || {% endif %}berdo_id || '-' || upgrade_id || '-' || perspective || '-' || energy_price || '-' || scenario
        as global_cost_key,
    *,
    max(global_cost_mid_usd) filter (where upgrade_id = 0)
        over (partition by {{ k_ }}berdo_id, perspective, energy_price, scenario)
        - global_cost_mid_usd as savings_vs_no_upgrade_usd,
    {% for c in costs -%}
    row_number() over (
        partition by {{ k_ }}berdo_id, perspective, energy_price, scenario
        -- rounded to the cent so float noise from the yearly sums can't break exact ties
        -- (e.g. Packages 2 and 4 in boiler buildings), which go to the lower upgrade id
        order by round(global_cost_{{ c }}_usd, 2), upgrade_id
    ) as cost_rank_{{ c }}{{ "," if not loop.last }}
    {% endfor -%}
from totals
{% endmacro %}
