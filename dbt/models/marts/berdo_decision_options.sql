-- The var("decision_period_start") retrofit decision for each matched BERDO building: the
-- four packages in comstock_package_components plus no retrofit (upgrade 0), each costed
-- over the 5-year standards period as installed cost + Alternative Compliance Payments on
-- the emissions still over the limit. Emissions and the ACP rate are held constant across
-- the period, installation is a one-time cost at its start, and nothing is discounted.
-- Grain: BERDO building x option.
{%- set costs = ["low", "mid", "high"] %}
with packages as (
    select
        berdo_id,
        upgrade_id,
        {% for c in costs -%}
        sum(installed_cost_{{ c }}_usd) as installed_cost_{{ c }}_usd{{ "," if not loop.last }}
        {% endfor -%}
    from {{ ref('int_berdo_package_costs') }}
    group by berdo_id, upgrade_id
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
        {% for c in costs -%}
        coalesce(p.installed_cost_{{ c }}_usd, 0) as installed_cost_{{ c }}_usd,
        {% endfor -%}
        co.acp_usd_per_year * (co.period_end - co.period_start + 1) as period_acp_usd
    from {{ ref('berdo_upgrade_compliance') }} as co
    left join {{ ref('berdo_upgrade_scenarios') }} as sc using (berdo_id, upgrade_id)
    left join packages as p using (berdo_id, upgrade_id)
    where co.period_start = {{ var("decision_period_start") }}
      and (
          co.upgrade_id = 0
          or co.upgrade_id in (select upgrade_id from {{ ref('comstock_package_components') }})
      )
),

totals as (
    select
        *,
        {% for c in costs -%}
        installed_cost_{{ c }}_usd + period_acp_usd as total_cost_{{ c }}_usd{{ "," if not loop.last }}
        {% endfor -%}
    from options
)

select
    berdo_id || '-' || upgrade_id as option_key,
    *,
    -- vs. paying ACPs on today's emissions with no retrofit
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
