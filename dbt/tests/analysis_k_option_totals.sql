-- Each option's total is its charged capital, existing-equipment charge, ACPs and energy
-- bills, at every k (to 5 cents: the exported parts and total are each rounded to the cent).
select k, berdo_id, upgrade_id
from {{ ref('analysis_k_cohort_options') }}
where total_cost_mid_usd is null
   or abs(capital_charged_mid_usd + existing_hvac_charged_mid_usd + period_acp_usd
          + period_energy_cost_usd - total_cost_mid_usd) > 0.05
