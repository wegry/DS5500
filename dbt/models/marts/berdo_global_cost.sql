-- EN 15459 global cost of each var("decision_period_start") option in berdo_decision_options,
-- as a present value at that start over var("global_cost_years") years:
--   installed cost + replacements - residual value      (per component, BTB lifetimes)
--   + sum over years t of (energy + O&M + emissions cost) / (1 + r)^t
-- Two perspectives, after the EU cost-optimal method (Delegated Regulation 244/2012):
-- financial pays BERDO Alternative Compliance Payments on emissions over each period's
-- standard at a private discount rate; societal prices all emissions at the social cost of
-- carbon at a low rate and leaves out ACPs, which are a transfer to the city.
-- Components are installed at the start and replaced at the end of each lifetime; the last
-- one is credited its straight-line remaining value at the horizon. Running costs fall at
-- the end of each year. The equipment the no-retrofit option keeps is never replaced, which
-- favors that option.
-- Energy scenarios (energy_scenarios seed): each year t, the electricity share of a
-- building's emissions falls by electricity_ef_decline a year (a cleaner grid, applied to
-- BERDO's electricity factor), and electricity and other fuel prices grow by their real
-- growth rates, all compounding from the decision year (t = 1 is today's level). Energy use
-- itself is held at the BERDO year's level. Scenario 'frozen' holds everything at today's
-- level and reproduces the original model; the others are illustrative sensitivities, not
-- Cambium or AEO projections.
-- Grain: BERDO building x option x perspective x energy price case x energy scenario.
{%- set costs = ["low", "mid", "high"] %}
{%- set n = var("global_cost_years") %}
{%- set start = var("decision_period_start") %}
{%- set fuels = ["electricity", "natural_gas", "oil_propane", "district_heating", "district_cooling"] %}
{#- fuels whose price follows electricity_price_growth; the rest follow fuel_price_growth #}
{%- set electric = ["electricity", "district_cooling"] %}
with perspectives as (
    select * from (values
        ('financial', {{ var("discount_rate_financial") }}),
        ('societal', {{ var("discount_rate_societal") }})
    ) as t (perspective, discount_rate)
),

price_cases as (
    select unnest(['low', 'mid', 'high']) as energy_price
),

scenarios as (
    select scenario, electricity_ef_decline, electricity_price_growth, fuel_price_growth
    from {{ ref('energy_scenarios') }}
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
    select * from {{ ref('berdo_decision_options') }}
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
        pc.berdo_id,
        pc.upgrade_id,
        f.perspective,
        {% for c in costs -%}
        sum(pc.installed_cost_{{ c }}_usd * f.capital_factor) as capital_pv_{{ c }}_usd{{ "," if not loop.last }}
        {% endfor -%}
    from {{ ref('int_berdo_package_costs') }} as pc
    inner join capital_factors as f using (btb_measure_id)
    group by pc.berdo_id, pc.upgrade_id, f.perspective
),

-- each option's yearly fuel use and emissions at today's grid, split into the electricity
-- part (which a cleaner grid shrinks) and the rest: the building's BERDO use and per-fuel
-- emissions scaled by the upgrade's per-fuel ratios (1 for no retrofit), as in
-- berdo_upgrade_scenarios
fuel_use as (
    select
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
    left join {{ ref('berdo_upgrade_scenarios') }} as sc using (berdo_id, upgrade_id)
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
        s.scenario,
        s.electricity_price_growth,
        s.fuel_price_growth,
        l.t,
        l.limit_kgco2e,
        fu.electric_ghg_kgco2e * power(1 - s.electricity_ef_decline, l.t - 1)
            + fu.other_ghg_kgco2e as ghg_kgco2e
    from fuel_use as fu
    cross join scenarios as s
    inner join limits as l using (berdo_id)
),

emissions as (
    select
        y.berdo_id,
        y.upgrade_id,
        y.scenario,
        p.perspective,
        sum(
            case p.perspective
                when 'financial' then greatest(y.ghg_kgco2e - y.limit_kgco2e, 0) / 1000
                    * {{ var("acp_usd_per_tco2e") }}
                else y.ghg_kgco2e / 1000 * {{ var("social_cost_usd_per_tco2e") }}
            end
            * power(1 + p.discount_rate, -y.t)
        ) as emissions_cost_pv_usd,
        count(*) filter (where y.ghg_kgco2e > y.limit_kgco2e) as years_over_limit
    from yearly as y
    cross join perspectives as p
    group by y.berdo_id, y.upgrade_id, y.scenario, p.perspective
),

energy as (
    select
        y.berdo_id,
        y.upgrade_id,
        y.scenario,
        p.perspective,
        pr.energy_price,
        sum(
            (
                (
                    {% for f in electric -%}
                    y.{{ f }}_kwh * pr.{{ f }}_usd_per_kwh{{ " +" if not loop.last }}
                    {% endfor -%}
                ) * power(1 + y.electricity_price_growth, y.t - 1)
                + (
                    {% for f in fuels if f not in electric -%}
                    y.{{ f }}_kwh * pr.{{ f }}_usd_per_kwh{{ " +" if not loop.last }}
                    {% endfor -%}
                ) * power(1 + y.fuel_price_growth, y.t - 1)
            )
            * power(1 + p.discount_rate, -y.t)
        ) as energy_pv_usd
    from yearly as y
    cross join perspectives as p
    cross join prices as pr
    group by y.berdo_id, y.upgrade_id, y.scenario, p.perspective, pr.energy_price
),

present_values as (
    select
        o.berdo_id,
        o.upgrade_id,
        o.upgrade_name,
        e.scenario,
        p.perspective,
        p.discount_rate,
        pr.energy_price,
        o.meets_standard as meets_standard_at_start,
        e.years_over_limit,
        -- present value of $1 a year for n years
        (1 - power(1 + p.discount_rate, -{{ n }})) / p.discount_rate as annuity_factor,
        {% for c in costs -%}
        o.installed_cost_{{ c }}_usd,
        coalesce(k.capital_pv_{{ c }}_usd, 0) as capital_pv_{{ c }}_usd,
        {% endfor -%}
        en.energy_pv_usd,
        e.emissions_cost_pv_usd
    from options as o
    cross join perspectives as p
    cross join price_cases as pr
    inner join emissions as e using (berdo_id, upgrade_id, perspective)
    inner join energy as en
        on en.berdo_id = o.berdo_id and en.upgrade_id = o.upgrade_id and en.scenario = e.scenario
        and en.perspective = p.perspective and en.energy_price = pr.energy_price
    left join capital as k using (berdo_id, upgrade_id, perspective)
),

totals as (
    select
        *,
        {% for c in costs -%}
        installed_cost_{{ c }}_usd * {{ var("om_share_per_year") }} * annuity_factor as om_pv_{{ c }}_usd,
        capital_pv_{{ c }}_usd
            + installed_cost_{{ c }}_usd * {{ var("om_share_per_year") }} * annuity_factor
            + energy_pv_usd
            + emissions_cost_pv_usd as global_cost_{{ c }}_usd{{ "," if not loop.last }}
        {% endfor -%}
    from present_values
)

select
    berdo_id || '-' || upgrade_id || '-' || perspective || '-' || energy_price || '-' || scenario
        as global_cost_key,
    *,
    max(global_cost_mid_usd) filter (where upgrade_id = 0)
        over (partition by berdo_id, perspective, energy_price, scenario)
        - global_cost_mid_usd as savings_vs_no_upgrade_usd,
    {% for c in costs -%}
    row_number() over (
        partition by berdo_id, perspective, energy_price, scenario
        -- rounded to the cent so float noise from the yearly sums can't break exact ties
        -- (e.g. Packages 2 and 4 in boiler buildings), which go to the lower upgrade id
        order by round(global_cost_{{ c }}_usd, 2), upgrade_id
    ) as cost_rank_{{ c }}{{ "," if not loop.last }}
    {% endfor -%}
from totals
