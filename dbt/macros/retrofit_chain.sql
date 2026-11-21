{#- The retrofit decision chain, from the matches to the five-year decision. Each model in the
    chain (berdo_upgrade_scenarios, int_berdo_package_costs, int_berdo_existing_hvac,
    berdo_upgrade_compliance, berdo_decision_options, berdo_decisions) calls one of these
    macros, as does its analysis_k_* twin, which runs the same SQL over matches for every
    neighbor count k (analysis_k_matches). With by_k the relations carry a k column, which
    every grouping, join and window then includes; without it the SQL is the production
    model's, unchanged. The models document what each step does. -#}

{% macro berdo_upgrade_scenarios(matches, by_k=false) %}
{%- set fuels = ["electricity", "natural_gas", "oil_propane", "district_heating", "district_cooling"] %}
with ratios as (
    select
        {% if by_k %}m.k,{% endif %}
        m.berdo_id,
        u.upgrade_id,
        any_value(u.upgrade_name) as upgrade_name,
        count(*) as matched_models,
        sum(m.match_weight * u.applicability::int) / nullif(sum(m.match_weight), 0) as applicable_share,
        {% for f in fuels -%}
        coalesce(sum(m.match_weight * u.{{ f }}_kwh) / nullif(sum(m.match_weight * b.{{ f }}_kwh), 0), 1) as {{ f }}_ratio,
        {% endfor -%}
        sum(m.match_weight * (u.eui_kwh_sqft / nullif(b.eui_kwh_sqft, 0))) / nullif(sum(m.match_weight), 0) as comstock_eui_ratio
    from {{ matches }} as m
    inner join {{ ref('int_comstock_models') }} as b
        on m.comstock_id = b.comstock_id and b.upgrade_id = 0
    inner join {{ ref('int_comstock_models') }} as u
        on m.comstock_id = u.comstock_id and u.upgrade_id > 0
    group by {% if by_k %}m.k, {% endif %}m.berdo_id, u.upgrade_id
),

projected as (
    select
        {% if by_k %}r.k,{% endif %}
        bl.berdo_id,
        bl.owner_name,
        bl.building_address,
        bl.property_type,
        bl.gfa_sqft,
        bl.compliance_standard_kgco2e_sqft,
        bl.eui_kwh_sqft as baseline_eui_kwh_sqft,
        bl.ghg_kgco2e as baseline_ghg_kgco2e,
        bl.ghg_intensity_kgco2e_sqft as baseline_ghg_intensity_kgco2e_sqft,
        r.upgrade_id,
        r.upgrade_name,
        r.upgrade_name like 'Package%' as is_package,
        -- ComStock's theoretical bound on HVAC savings, not an installable measure
        r.upgrade_name = 'Ideal Thermal Air Loads' as is_theoretical,
        r.matched_models,
        r.applicable_share,
        {% for f in fuels -%}
        r.{{ f }}_ratio,
        {% endfor -%}
        (
            {% for f in fuels -%}
            bl.{{ f }}_kwh * r.{{ f }}_ratio{{ " +" if not loop.last }}
            {% endfor -%}
        ) / bl.gfa_sqft as projected_eui_kwh_sqft,
        {% for f in fuels -%}
        bl.{{ f }}_ghg_kgco2e * r.{{ f }}_ratio{{ " +" if not loop.last }}
        {% endfor -%}
            as projected_ghg_kgco2e
    from {{ ref('int_berdo_match_buildings') }} as bl
    inner join ratios as r using (berdo_id)
)

select
    {% if by_k %}k || '-' || {% endif %}berdo_id || '-' || upgrade_id as scenario_key,
    *,
    projected_ghg_kgco2e / gfa_sqft as projected_ghg_intensity_kgco2e_sqft,
    1 - projected_ghg_kgco2e / baseline_ghg_kgco2e as ghg_reduction_pct,
    baseline_ghg_intensity_kgco2e_sqft <= compliance_standard_kgco2e_sqft as meets_standard_now,
    projected_ghg_kgco2e / gfa_sqft <= compliance_standard_kgco2e_sqft as meets_standard_after
from projected
{% endmacro %}


{% macro berdo_package_costs(matches, by_k=false) %}
select
    {% if by_k %}m.k || '-' || {% endif %}m.berdo_id || '-' || c.upgrade_id || '-' || c.measure as berdo_component_key,
    {% if by_k %}m.k,{% endif %}
    m.berdo_id,
    c.upgrade_id,
    any_value(c.package_name) as package_name,
    c.component,
    c.measure,
    any_value(c.btb_measure_id) as btb_measure_id,
    count(*) as matched_models,
    sum(m.match_weight * c.applicability::int) / nullif(sum(m.match_weight), 0) as applicable_share,
    {% for cost in ["low", "mid", "high"] -%}
    sum(m.match_weight * c.installed_cost_{{ cost }}_usd) / nullif(sum(m.match_weight * c.gfa_sqft), 0) as installed_cost_{{ cost }}_usd_per_sqft,
    sum(m.match_weight * c.installed_cost_{{ cost }}_usd) / nullif(sum(m.match_weight * c.gfa_sqft), 0) * any_value(b.gfa_sqft)
        as installed_cost_{{ cost }}_usd{{ "," if not loop.last }}
    {% endfor -%}
from {{ matches }} as m
inner join {{ ref('int_berdo_match_buildings') }} as b using (berdo_id)
inner join {{ ref('int_comstock_package_costs') }} as c using (comstock_id)
group by {% if by_k %}m.k, {% endif %}m.berdo_id, c.upgrade_id, c.component, c.measure
{% endmacro %}


{% macro berdo_existing_hvac(matches, by_k=false) %}
with sizes as (
    select
        pm.comstock_id,
        s.measure,
        avg(pm.quantity) * any_value(s.capacity_per_quantity) as capacity,
        any_value(pm.gfa_sqft) as gfa_sqft
    from {{ ref('stg_comstock__package_measures') }} as pm
    inner join {{ ref('existing_hvac_like_for_like') }} as s
        on pm.measure = s.measure and pm.upgrade_id = s.quantity_upgrade_id
    group by pm.comstock_id, s.measure
),

pooled as (
    select
        {% if by_k %}m.k,{% endif %}
        m.berdo_id,
        s.measure,
        sum(m.match_weight * s.capacity) / nullif(sum(m.match_weight * s.gfa_sqft), 0)
            * any_value(b.gfa_sqft) as capacity
    from {{ matches }} as m
    inner join sizes as s using (comstock_id)
    inner join {{ ref('int_berdo_match_buildings') }} as b using (berdo_id)
    group by {% if by_k %}m.k, {% endif %}m.berdo_id, s.measure
)

select
    {% if by_k %}p.k || '-' || {% endif %}p.berdo_id || '-' || p.measure as existing_hvac_key,
    {% if by_k %}p.k,{% endif %}
    p.berdo_id,
    p.measure,
    l.btb_measure_id,
    l.existing_equipment,
    p.capacity,
    u.cost_unit,
    {% for c in ["low", "mid", "high"] -%}
    p.capacity * u.unit_cost_{{ c }}_usd as replacement_cost_{{ c }}_usd,
    {% endfor -%}
    u.lifetime_years,
    {{ var("existing_hvac_remaining_years") }}::double as remaining_years
from pooled as p
inner join {{ ref('existing_hvac_like_for_like') }} as l using (measure)
inner join {{ ref('int_btb_unit_costs') }} as u using (btb_measure_id)
where {{ var("like_for_like_hvac", true) }}
{% endmacro %}


{% macro berdo_upgrade_compliance(scenarios, matches, by_k=false) %}
{%- set k_ = "k, " if by_k else "" %}
with scenarios as (
    select
        {% if by_k %}sc.k,{% endif %}
        sc.berdo_id,
        sc.gfa_sqft,
        sc.upgrade_id,
        sc.upgrade_name,
        sc.is_package,
        sc.is_theoretical,
        sc.projected_ghg_kgco2e,
        bl.electricity_ghg_kgco2e * sc.electricity_ratio as electricity_ghg_kgco2e
    from {{ scenarios }} as sc
    inner join {{ ref('int_berdo_match_buildings') }} as bl using (berdo_id)

    union all

    select
        {% if by_k %}ks.k,{% endif %}
        berdo_id,
        gfa_sqft,
        0 as upgrade_id,
        'No upgrade' as upgrade_name,
        false as is_package,
        false as is_theoretical,
        ghg_kgco2e as projected_ghg_kgco2e,
        electricity_ghg_kgco2e
    from {{ ref('int_berdo_match_buildings') }}
    {% if by_k %}cross join (select distinct k from {{ matches }}) as ks{% endif %}
),

periods as (
    select
        sc.*,
        st.building_use,
        st.period_start,
        st.period_end,
        st.is_compliance_period,
        st.standard_source,
        st.standard_kgco2e_sqft,
        ix.electricity_index,
        -- emissions as BERDO counts them in the period's first year
        sc.projected_ghg_kgco2e - sc.electricity_ghg_kgco2e * (1 - ix.electricity_index)
            as period_ghg_kgco2e
    from scenarios as sc
    inner join {{ ref('int_berdo_building_standards') }} as st using (berdo_id)
    inner join {{ ref('int_berdo_electricity_index') }} as ix on ix.year = st.period_start
),

-- each year of the period at that year's electricity factor
yearly as (
    select
        {% if by_k %}p.k,{% endif %}
        p.berdo_id,
        p.upgrade_id,
        p.period_start,
        sum(greatest(
            p.projected_ghg_kgco2e - p.electricity_ghg_kgco2e * (1 - iy.electricity_index)
                - p.standard_kgco2e_sqft * p.gfa_sqft,
            0
        )) / 1000 * {{ var("acp_usd_per_tco2e") }} as period_acp_usd
    from periods as p
    inner join {{ ref('int_berdo_electricity_index') }} as iy
        on iy.year between p.period_start and p.period_end
    group by {% if by_k %}p.k, {% endif %}p.berdo_id, p.upgrade_id, p.period_start
)

select
    {% if by_k %}k || '-' || {% endif %}berdo_id || '-' || upgrade_id || '-' || period_start as compliance_key,
    {% if by_k %}k,{% endif %}
    berdo_id,
    upgrade_id,
    upgrade_name,
    is_package,
    is_theoretical,
    building_use,
    period_start,
    period_end,
    is_compliance_period,
    standard_source,
    standard_kgco2e_sqft,
    electricity_index,
    period_ghg_kgco2e / gfa_sqft as projected_ghg_intensity_kgco2e_sqft,
    period_ghg_kgco2e / gfa_sqft <= standard_kgco2e_sqft as meets_standard,
    greatest(period_ghg_kgco2e - standard_kgco2e_sqft * gfa_sqft, 0) as excess_kgco2e,
    -- annual payment if the excess is covered with Alternative Compliance Payments
    greatest(period_ghg_kgco2e - standard_kgco2e_sqft * gfa_sqft, 0) / 1000
        * {{ var("acp_usd_per_tco2e") }} as acp_usd_per_year,
    y.period_acp_usd
from periods
left join yearly as y using ({{ k_ }}berdo_id, upgrade_id, period_start)
{% endmacro %}


{% macro berdo_decision_options(compliance, scenarios, package_costs, existing_hvac, by_k=false) %}
{%- set k_ = "k, " if by_k else "" %}
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
        {% if by_k %}pc.k,{% endif %}
        pc.berdo_id,
        pc.upgrade_id,
        {% for c in costs -%}
        sum(pc.installed_cost_{{ c }}_usd) as installed_cost_{{ c }}_usd,
        {% endfor -%}
        {% for c in costs -%}
        sum(pc.installed_cost_{{ c }}_usd * {{ capital_share }}) as capital_charged_{{ c }}_usd
            {{- "," if not loop.last }}
        {% endfor -%}
    from {{ package_costs }} as pc
    inner join {{ ref('int_btb_unit_costs') }} as u using (btb_measure_id)
    inner join {{ ref('int_berdo_building_standards') }} as st
        on st.berdo_id = pc.berdo_id and st.period_start = {{ var("decision_period_start") }}
    group by {% if by_k %}pc.k, {% endif %}pc.berdo_id, pc.upgrade_id
),

-- the share of the existing equipment's like-for-like replacement the period bears
existing as (
    select
        {% if by_k %}e.k,{% endif %}
        e.berdo_id,
        {% for c in costs -%}
        sum(e.replacement_cost_{{ c }}_usd * {{ existing_share }}) as existing_hvac_charged_{{ c }}_usd
            {{- "," if not loop.last }}
        {% endfor -%}
    from {{ existing_hvac }} as e
    inner join {{ ref('int_btb_unit_costs') }} as u using (btb_measure_id)
    inner join {{ ref('int_berdo_building_standards') }} as st
        on st.berdo_id = e.berdo_id and st.period_start = {{ var("decision_period_start") }}
    group by {% if by_k %}e.k, {% endif %}e.berdo_id
),

hvac_upgrades as (
    select distinct upgrade_id
    from {{ ref('comstock_package_components') }}
    where measure in ('{{ var("hvac_replacing_measures") | join("', '") }}')
),

options as (
    select
        {% if by_k %}co.k,{% endif %}
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
        -- the capital method, so Python checks (monte_carlo_inputs.py) can mirror this build
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
    from {{ compliance }} as co
    inner join {{ ref('int_berdo_match_buildings') }} as bl using (berdo_id)
    left join {{ scenarios }} as sc using ({{ k_ }}berdo_id, upgrade_id)
    left join packages as p using ({{ k_ }}berdo_id, upgrade_id)
    left join existing as ex using ({{ k_ }}berdo_id)
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
    {% if by_k %}k || '-' || {% endif %}berdo_id || '-' || upgrade_id as option_key,
    *,
    max(energy_cost_mid_usd_per_year) filter (where upgrade_id = 0) over (partition by {{ k_ }}berdo_id)
        - energy_cost_mid_usd_per_year as energy_savings_usd_per_year,
    -- vs. paying ACPs and energy bills on today's emissions and use with no retrofit
    max(total_cost_mid_usd) filter (where upgrade_id = 0) over (partition by {{ k_ }}berdo_id)
        - total_cost_mid_usd as savings_vs_no_upgrade_usd,
    {% for c in costs -%}
    -- ties (e.g. two options that both meet the standard at no cost) go to lower emissions,
    -- then the lower upgrade id; rounded, as in berdo_global_cost, so float noise from the
    -- pooled sums can't break exact ties (e.g. Packages 2 and 4 where only LEDs apply)
    row_number() over (
        partition by {{ k_ }}berdo_id
        order by round(total_cost_{{ c }}_usd, 2), round(projected_ghg_intensity_kgco2e_sqft, 9),
            upgrade_id
    ) as cost_rank_{{ c }}{{ "," if not loop.last }}
    {% endfor -%}
from totals
{% endmacro %}


{% macro berdo_decisions(options, by_k=false) %}
{%- set k_ = "k, " if by_k else "" %}
with best as (
    select * from {{ options }} where cost_rank_mid = 1
),

no_upgrade as (
    select {{ k_ }}berdo_id, total_cost_mid_usd, period_acp_usd, meets_standard
    from {{ options }}
    where upgrade_id = 0
),

{% for c in ["low", "high"] -%}
best_{{ c }} as (
    select {{ k_ }}berdo_id, upgrade_id, upgrade_name
    from {{ options }}
    where cost_rank_{{ c }} = 1
){{ "," if not loop.last }}
{% endfor %}

select
    {% if by_k %}b.k,{% endif %}
    b.berdo_id,
    bl.owner_name,
    bl.building_address,
    bl.property_type,
    bl.gfa_sqft,
    b.period_start,
    b.period_end,
    b.is_compliance_period,
    b.standard_kgco2e_sqft,
    bl.ghg_intensity_kgco2e_sqft as baseline_ghg_intensity_kgco2e_sqft,
    n.meets_standard as meets_standard_without_upgrade,
    b.upgrade_id as recommended_upgrade_id,
    case when b.upgrade_id = 0 then 'No upgrade (ACP only)' else b.upgrade_name end
        as recommended_option,
    b.projected_ghg_intensity_kgco2e_sqft,
    b.meets_standard,
    b.applicable_share,
    b.installed_cost_mid_usd,
    b.capital_charged_mid_usd,
    b.period_acp_usd,
    b.period_energy_cost_usd,
    b.energy_savings_usd_per_year,
    b.total_cost_mid_usd,
    n.total_cost_mid_usd as no_upgrade_total_cost_usd,
    n.total_cost_mid_usd - b.total_cost_mid_usd as savings_vs_no_upgrade_usd,
    lo.upgrade_id as recommended_upgrade_id_low_cost,
    hi.upgrade_id as recommended_upgrade_id_high_cost,
    lo.upgrade_id = b.upgrade_id and hi.upgrade_id = b.upgrade_id as is_robust_to_cost
from best as b
inner join {{ ref('int_berdo_match_buildings') }} as bl using (berdo_id)
inner join no_upgrade as n using ({{ k_ }}berdo_id)
inner join best_low as lo using ({{ k_ }}berdo_id)
inner join best_high as hi using ({{ k_ }}berdo_id)
{% endmacro %}
