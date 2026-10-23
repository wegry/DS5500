-- Each package component's ComStock quantity must be in the unit its BTB cost is per.
select comstock_component_key, quantity_unit, cost_unit
from {{ ref('int_comstock_package_costs') }}
where quantity_unit is distinct from cost_unit
