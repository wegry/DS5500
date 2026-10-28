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
-- the end of each year. Prices, energy use and emissions are held at today's level (BERDO's
-- electricity factor will fall, so later emissions costs are upper bounds), and the
-- equipment the no-retrofit option keeps is never replaced, which favors that option.
-- Grain: BERDO building x option x perspective x energy price case.
{%- set costs = ["low", "mid", "high"] %}
{%- set n = var("global_cost_years") %}
{%- set start = var("decision_period_start") %}
with perspectives as (
    select * from (values
        ('financial', {{ var("discount_rate_financial") }}),
        ('societal', {{ var("discount_rate_societal") }})
    ) as t (perspective, discount_rate)
),

price_cases as (
    select unnest(['low', 'mid', 'high']) as energy_price
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

emissions as (
    select
        co.berdo_id,
        co.upgrade_id,
        p.perspective,
        sum(
            case p.perspective
                when 'financial' then co.acp_usd_per_year
                else co.projected_ghg_intensity_kgco2e_sqft * bl.gfa_sqft / 1000
                    * {{ var("social_cost_usd_per_tco2e") }}
            end
            * power(1 + p.discount_rate, -y.t)
        ) as emissions_cost_pv_usd,
        count(*) filter (where not co.meets_standard) as years_over_limit
    from {{ ref('berdo_upgrade_compliance') }} as co
    inner join {{ ref('int_berdo_match_buildings') }} as bl using (berdo_id)
    inner join years as y on y.year between co.period_start and coalesce(co.period_end, y.year)
    cross join perspectives as p
    where co.upgrade_id in (select upgrade_id from options)
    group by co.berdo_id, co.upgrade_id, p.perspective
),

present_values as (
    select
        o.berdo_id,
        o.upgrade_id,
        o.upgrade_name,
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
        case pr.energy_price
            {% for c in costs -%}
            when '{{ c }}' then o.energy_cost_{{ c }}_usd_per_year
            {% endfor -%}
        end * annuity_factor as energy_pv_usd,
        e.emissions_cost_pv_usd
    from options as o
    cross join perspectives as p
    cross join price_cases as pr
    inner join emissions as e using (berdo_id, upgrade_id, perspective)
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
    berdo_id || '-' || upgrade_id || '-' || perspective || '-' || energy_price as global_cost_key,
    *,
    max(global_cost_mid_usd) filter (where upgrade_id = 0)
        over (partition by berdo_id, perspective, energy_price)
        - global_cost_mid_usd as savings_vs_no_upgrade_usd,
    {% for c in costs -%}
    row_number() over (
        partition by berdo_id, perspective, energy_price
        order by global_cost_{{ c }}_usd, upgrade_id
    ) as cost_rank_{{ c }}{{ "," if not loop.last }}
    {% endfor -%}
from totals
