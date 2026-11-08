# Package 5 cost assumptions

ComStock upgrade 58: heat pumps, economizer, DCV,
and exhaust-air energy recovery.

## BTB costs
Source: https://data.openei.org/submissions/8342

- ID 7: Demand-controlled ventilation, $39,810 / 16,000 sqft.
- ID 5: Energy recovery wheel, $66,874 / 11,000 CFM.
- IDs 2, 3: Existing heat-pump RTU and heat-pump boiler mappings.
  (Package 5 has no LED lighting, so BTB ID 12 is not used.)

Airflow is estimated from ComStock's outdoor-air-flow-rate
intensity multiplied by building floor area.

## Imputed economizer costs
- $500 per economizer air loop used as a hardware proxy.
  Source: California Energy Commission, 2023, CEC-500-2023-043.
  https://www.energy.ca.gov/sites/default/files/2023-06/CEC-500-2023-043.pdf

- $10,000 per building for controls programming and commissioning.
  Source: Energy and Buildings (2022), article 112270.
  https://doi.org/10.1016/j.enbuild.2022.112270

## Limitations
The $500 figure comes from small RTU applications, so using
it per ComStock air loop is an approximation.
The $10,000 covers controls work, not necessarily full
economizer hardware installation.
Low/high ranges and 15-year lifetimes are modeling assumptions.
BTB and external studies use different price years.
Energy recovery wheel is a proxy for ComStock's broader
energy-or-heat-recovery measure.
Costs are exploratory and not building-specific quotes.

## Cost calculation and sensitivity

DCV:
BTB ID 7: $39,810 / 16,000 sqft = $2.49/sqft.
Applied to ComStock floor area when DCV is applicable.

Energy recovery:
BTB ID 5: $66,874 / 11,000 CFM = $6.08/CFM.
ComStock airflow intensity is multiplied by floor area
and converted from m3/s to CFM.

Economizer hardware (imputed):
$500 x max(number of economizer air loops, 1),
only when ComStock reports economizer applicability.

Economizer controls (imputed):
$10,000 per applicable simulated building model.
Component costs are subsequently pooled across matched
ComStock buildings and scaled to BERDO floor area.

Sensitivity analysis:
Hardware low/mid/high: $250 / $500 / $1,000 per loop.
Controls low/mid/high: $5,000 / $10,000 / $15,000.

These ranges are modeling assumptions, not published
confidence intervals. The hardware proxy originates from
small rooftop units, so scaling it to larger air loops is
uncertain. BTB costs and external benchmarks may also have
different price years.

Reproduce using:
uv run python check_cost_sensitivity.py

For Package 5 the script varies the entire installation
cost (all components, BTB and imputed) between low and
high, holding energy costs and all other upgrades at mid.
