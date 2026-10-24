
-- Check that applicable retrofit components have
-- valid quantities and installation costs.
-- The test passes when zero rows are returned.

select
    comstock_id,
    upgrade_id,
    component,
    quantity,
    installed_cost_low_usd,
    installed_cost_mid_usd,
    installed_cost_high_usd

from {{ ref('int_comstock_package_costs') }}

where upgrade_id in (43, 48, 49, 52, 54, 55, 56, 57)
  and applicability
  and (
      quantity is null
      or quantity < 0
      or installed_cost_low_usd is null
      or installed_cost_mid_usd is null
      or installed_cost_high_usd is null
      or installed_cost_low_usd < 0
      or installed_cost_mid_usd < 0
      or installed_cost_high_usd < 0
      or (
          quantity > 0
          and (
              installed_cost_low_usd = 0
              or installed_cost_mid_usd = 0
              or installed_cost_high_usd = 0
          )
      )
  )
