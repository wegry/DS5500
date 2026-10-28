
-- Economic evaluation of four standalone ComStock upgrades.
-- Cohort: BERDO offices exceeding the 2030 standard.
-- Compare installed costs with 5-year avoided ACPs and energy bills.
-- Low, mid, and high costs are evaluated separately.

with baseline as (
    select
        berdo_id,
        period_acp_usd as baseline_acp_usd,
        total_cost_low_usd as baseline_low,
        total_cost_mid_usd as baseline_mid,
        total_cost_high_usd as baseline_high
    from {{ ref('berdo_decision_options') }}
    where upgrade_id = 0
      and not meets_standard
),

retrofits as (
    select
        o.*,
        b.baseline_acp_usd,
        b.baseline_low,
        b.baseline_mid,
        b.baseline_high
    from {{ ref('berdo_decision_options') }} as o
    inner join baseline as b using (berdo_id)
    where o.upgrade_id in (43, 48, 49, 52)
)

select
    upgrade_id,
    any_value(upgrade_name) as upgrade_name,
    count(distinct berdo_id) as buildings,
    round(median(installed_cost_mid_usd), 0)
        as median_install_cost_usd,
    round(median(baseline_acp_usd - period_acp_usd), 0)
        as median_avoided_acp_usd,
    round(median(energy_savings_usd_per_year * period_years), 0)
        as median_avoided_energy_cost_usd,
    round(median(total_cost_mid_usd - baseline_mid), 0)
        as median_extra_cost_usd,
    count(*) filter (
        where total_cost_low_usd < baseline_low
    ) as cheaper_low,
    count(*) filter (
        where total_cost_mid_usd < baseline_mid
    ) as cheaper_mid,
    count(*) filter (
        where total_cost_high_usd < baseline_high
    ) as cheaper_high
from retrofits
group by upgrade_id
order by upgrade_id
