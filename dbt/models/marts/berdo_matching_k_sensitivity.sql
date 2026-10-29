
-- Evaluate sensitivity of retrofit emissions projections
-- to the number of BERDO-ComStock neighbors.
-- Uses the same fuel-specific methodology as
-- berdo_upgrade_scenarios, and prices energy like
-- berdo_decision_options (mid prices).

{% set fuels = [
    "electricity",
    "natural_gas",
    "oil_propane",
    "district_heating",
    "district_cooling"
] %}
with prices as (
    select
        {% for f in fuels -%}
        max(usd_per_kwh_mid) filter (where fuel = '{{ f }}') as {{ f }}_usd_per_kwh{{ "," if not loop.last }}
        {% endfor -%}
    from {{ ref('fuel_prices') }}
),
k_values as (
    select unnest(range(1, 11)) as k
),
ratios as (
    select
        m.berdo_id,
        k.k,
        u.upgrade_id,
        count(*) as matched_models,
        {% for f in fuels %}
        coalesce(
            sum(u.{{ f }}_kwh)
            / nullif(sum(b.{{ f }}_kwh), 0),
            1
        ) as {{ f }}_ratio
        {{ "," if not loop.last }}
        {% endfor %}
    from {{ ref('int_berdo_comstock_matches') }} m
    cross join k_values k
    inner join {{ ref('int_comstock_models') }} b
        on m.comstock_id = b.comstock_id
        and b.upgrade_id = 0
    inner join {{ ref('int_comstock_models') }} u
        on m.comstock_id = u.comstock_id
        and u.upgrade_id in (
            43, 48, 49, 52, 54, 55, 56, 57
        )
    where m.match_rank <= k.k
    group by m.berdo_id, k.k, u.upgrade_id
),
projected as (
    select
        bl.berdo_id,
        r.k,
        r.upgrade_id,
        r.matched_models,

        bl.ghg_kgco2e as baseline_ghg_kgco2e,
        bl.gfa_sqft,
        -- the decision period's standard, not the disclosed 2025-2029 one
        st.standard_kgco2e_sqft as compliance_standard_kgco2e_sqft,
        (
            {% for f in fuels %}
            bl.{{ f }}_ghg_kgco2e
                * r.{{ f }}_ratio
            {{ "+" if not loop.last }}
            {% endfor %}
        ) as projected_ghg_kgco2e,
        (
            {% for f in fuels %}
            bl.{{ f }}_kwh
                * r.{{ f }}_ratio
                * p.{{ f }}_usd_per_kwh
            {{ "+" if not loop.last }}
            {% endfor %}
        ) as projected_energy_cost_usd_per_year
    from {{ ref('int_berdo_match_buildings') }} bl
    inner join ratios r
        on bl.berdo_id = r.berdo_id
    inner join {{ ref('int_berdo_building_standards') }} st
        on bl.berdo_id = st.berdo_id
        and st.period_start = {{ var("decision_period_start") }}
    cross join prices p
)
select
    berdo_id,
    k,
    upgrade_id,
    matched_models,
    baseline_ghg_kgco2e,
    projected_ghg_kgco2e,
    projected_energy_cost_usd_per_year,
    1 - projected_ghg_kgco2e
        / nullif(baseline_ghg_kgco2e, 0)
        as ghg_reduction_pct,
    projected_ghg_kgco2e / nullif(gfa_sqft, 0)
        <= compliance_standard_kgco2e_sqft
        as meets_standard_after
from projected
