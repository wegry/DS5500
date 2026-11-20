-- The var("decision_period_start") retrofit decision for each matched BERDO building: the
-- upgrades in comstock_package_components plus no retrofit (upgrade 0), each costed
-- over the 5-year standards period as installed cost + Alternative Compliance Payments on
-- the emissions still over the limit + energy bills. Energy use, prices and the ACP rate
-- are held constant across the period; the electricity part of the emissions follows
-- BERDO's projected factor year by year (berdo_upgrade_compliance.period_acp_usd), while
-- meets_standard and the intensity are the period's first year, its highest-factor year.
-- Running costs are not discounted. Equipment outlives the period (BTB lifetimes, median
-- ~21 years), so var("five_year_capital") sets how much of each component's installed cost
-- the period bears (capital_charged_*): 'annualized' charges period_years equivalent annual
-- costs at var("discount_rate_financial") (installed x r / (1 - (1 + r)^-lifetime) a year);
-- 'straight_line' charges period_years / lifetime of it, i.e. credits straight-line
-- remaining value at the period's end as berdo_global_cost does at its horizon; 'full'
-- charges all of it. Each is capped at the installed cost. Options that keep the existing
-- heating and cooling equipment (replaces_hvac false) are charged its like-for-like
-- replacement (int_berdo_existing_hvac) the same way (existing_hvac_charged_*), since it
-- wears out too; heat pump, VRF and geothermal options replace it instead, so in effect they
-- pay only their extra cost over like-for-like. With 'full' there is no such charge: when
-- the existing equipment fails in the period is unknown. Totals vary the installed costs
-- (low/mid/high) at mid energy prices; energy_cost_{low,high}_usd_per_year give the price
-- range.
-- Energy bills price the building's BERDO fuel use, scaled by the upgrade's per-fuel ratios
-- (1 for no retrofit), at the fuel_prices seed's flat $/kWh, so they leave out demand
-- charges and tariff structure. Grain: BERDO building x option.
{%- set costs = ["low", "mid", "high"] %}
{%- set fuels = ["electricity", "natural_gas", "oil_propane", "district_heating", "district_cooling"] %}
{%- set capital = var("five_year_capital", "annualized") %}
{%- set years = "(st.period_end - st.period_start + 1)" %}
{%- if capital == "annualized" %}
{%- set r = var("discount_rate_financial") %}
{%- set capital_share = "least(1, " ~ years ~ " * " ~ r ~ " / (1 - power(1 + " ~ r ~ ", -u.lifetime_years)))" %}
{%- elif capital == "straight_line" %}
{%- set capital_share = "least(1, " ~ years ~ " / u.lifetime_years)" %}
{%- elif capital == "full" %}
{%- set capital_share = "1" %}
{%- else %}
{{ exceptions.raise_compiler_error("five_year_capital must be annualized, straight_line or full") }}
{%- endif %}
{%- set existing_share = "0" if capital == "full" else capital_share %}
with prices as (
    select
        {% for c in costs -%}
        {% for f in fuels -%}
        max(usd_per_kwh_{{ c }}) filter (where fuel = '{{ f }}') as {{ f }}_{{ c }}{{ "," if not loop.last }}
        {% endfor -%}
        {{ "," if not loop.last }}
        {% endfor -%}
    from {{ ref('fuel_prices') }}
),

packages as (
    select
        pc.berdo_id,
        pc.upgrade_id,
        {% for c in costs -%}
        sum(pc.installed_cost_{{ c }}_usd) as installed_cost_{{ c }}_usd,
        {% endfor -%}
        {% for c in costs -%}
        sum(pc.installed_cost_{{ c }}_usd * {{ capital_share }}) as capital_charged_{{ c }}_usd
            {{- "," if not loop.last }}
        {% endfor -%}
    from {{ ref('int_berdo_package_costs') }} as pc
    inner join {{ ref('int_btb_unit_costs') }} as u using (btb_measure_id)
    inner join {{ ref('int_berdo_building_standards') }} as st
        on st.berdo_id = pc.berdo_id and st.period_start = {{ var("decision_period_start") }}
    group by pc.berdo_id, pc.upgrade_id
),

-- the share of the existing equipment's like-for-like replacement the period bears
existing as (
    select
        e.berdo_id,
        {% for c in costs -%}
        sum(e.replacement_cost_{{ c }}_usd * {{ existing_share }}) as existing_hvac_charged_{{ c }}_usd
            {{- "," if not loop.last }}
        {% endfor -%}
    from {{ ref('int_berdo_existing_hvac') }} as e
    inner join {{ ref('int_btb_unit_costs') }} as u using (btb_measure_id)
    inner join {{ ref('int_berdo_building_standards') }} as st
        on st.berdo_id = e.berdo_id and st.period_start = {{ var("decision_period_start") }}
    group by e.berdo_id
),

hvac_upgrades as (
    select distinct upgrade_id
    from {{ ref('comstock_package_components') }}
    where measure in ('{{ var("hvac_replacing_measures") | join("', '") }}')
),

options as (
    select
        co.berdo_id,
        co.upgrade_id,
        co.upgrade_name,
        co.period_start,
        co.period_end,
        co.period_end - co.period_start + 1 as period_years,
        co.is_compliance_period,
        co.standard_kgco2e_sqft,
        co.projected_ghg_intensity_kgco2e_sqft,
        co.meets_standard,
        co.excess_kgco2e,
        co.acp_usd_per_year,
        sc.applicable_share,
        sc.ghg_reduction_pct,
        co.upgrade_id in (select upgrade_id from hvac_upgrades) as replaces_hvac,
        {% for c in costs -%}
        coalesce(p.installed_cost_{{ c }}_usd, 0) as installed_cost_{{ c }}_usd,
        coalesce(p.capital_charged_{{ c }}_usd, 0) as capital_charged_{{ c }}_usd,
        case when co.upgrade_id in (select upgrade_id from hvac_upgrades) then 0
            else coalesce(ex.existing_hvac_charged_{{ c }}_usd, 0)
        end as existing_hvac_charged_{{ c }}_usd,
        {% endfor -%}
        co.period_acp_usd,
        -- the capital method, so Python checks (monte_carlo.py) can mirror this build
        '{{ capital }}' as five_year_capital,
        {{ var("discount_rate_financial") if capital == "annualized" else "null" }}::double
            as capital_discount_rate,
        {% for c in costs -%}
        (
            {% for f in fuels -%}
            bl.{{ f }}_kwh * coalesce(sc.{{ f }}_ratio, 1) * pr.{{ f }}_{{ c }}{{ " +" if not loop.last }}
            {% endfor -%}
        ) as energy_cost_{{ c }}_usd_per_year{{ "," if not loop.last }}
        {% endfor -%}
    from {{ ref('berdo_upgrade_compliance') }} as co
    inner join {{ ref('int_berdo_match_buildings') }} as bl using (berdo_id)
    left join {{ ref('berdo_upgrade_scenarios') }} as sc using (berdo_id, upgrade_id)
    left join packages as p using (berdo_id, upgrade_id)
    left join existing as ex using (berdo_id)
    cross join prices as pr
    where co.period_start = {{ var("decision_period_start") }}
      and (
          co.upgrade_id = 0
          or co.upgrade_id in (select upgrade_id from {{ ref('comstock_package_components') }})
      )
      -- the expanded upgrades are offered only where some matched model applies them
      and (
          co.upgrade_id not in ({{ var("expanded_upgrade_ids") | join(", ") }})
          or (
              coalesce(sc.applicable_share, 0) > 0
              and coalesce(p.installed_cost_mid_usd, 0) > 0
          )
      )
),

energy as (
    select
        *,
        energy_cost_mid_usd_per_year * period_years as period_energy_cost_usd
    from options
),

totals as (
    select
        *,
        {% for c in costs -%}
        capital_charged_{{ c }}_usd + existing_hvac_charged_{{ c }}_usd + period_acp_usd
            + period_energy_cost_usd
            as total_cost_{{ c }}_usd{{ "," if not loop.last }}
        {% endfor -%}
    from energy
)

select
    berdo_id || '-' || upgrade_id as option_key,
    *,
    max(energy_cost_mid_usd_per_year) filter (where upgrade_id = 0) over (partition by berdo_id)
        - energy_cost_mid_usd_per_year as energy_savings_usd_per_year,
    -- vs. paying ACPs and energy bills on today's emissions and use with no retrofit
    max(total_cost_mid_usd) filter (where upgrade_id = 0) over (partition by berdo_id)
        - total_cost_mid_usd as savings_vs_no_upgrade_usd,
    {% for c in costs -%}
    -- ties (e.g. two options that both meet the standard at no cost) go to lower emissions
    row_number() over (
        partition by berdo_id
        order by total_cost_{{ c }}_usd, projected_ghg_intensity_kgco2e_sqft, upgrade_id
    ) as cost_rank_{{ c }}{{ "," if not loop.last }}
    {% endfor -%}
from totals
