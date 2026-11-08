# Geothermal retrofit cost sources

## ComStock upgrade 29: Packaged ground-source heat pump

### 1. Heat-pump equipment — BTB

Source: 2024 Buildings Technology Baseline, commercial dataset.
https://data.openei.org/submissions/8342

Technology/Measure ID: 10
Technology: Commercial Ground Source Heat Pump
Scenario: Reference, projection year 2030
Currency: 2023 USD

Typical installed cost: $51,600 for a 4-ton reference system.
Derived unit cost: $12,900/ton.

BTB explicitly states: "No ground heat exchanger."

### 2. Ground-loop installation — Imputed

Source: U.S. Department of Energy (2025).
Pathways to Commercial Liftoff: Geothermal Heating and Cooling.
Executive Summary, Figure ES5, page 6.

https://www.energy.gov/sites/default/files/2025-07/LIFTOFF_DOE_Geothermal-Heating-and-Cooling.pdf

Commercial ground-loop supplies, drilling and installation:
$5,100 per cooling ton (national illustrative median).

### 3. Our calculation

Heat pump: $12,900/ton
Ground loop: $5,100/ton
Combined midpoint: $18,000/ton

Ground-loop sensitivity:
Low: $3,570/ton
Mid: $5,100/ton
High: $6,630/ton

The +/-30% range and 50-year ground-loop lifetime are
modeling assumptions, not values established by DOE.

### Limitations

- The sources may use different price years.
- Linear cost scaling is assumed.
- Boston-specific drilling and site constraints are not modeled.
- Geothermal feasibility is not verified for individual BERDO buildings.
- No tax incentives are deducted.
- DOE also reports $7,900/ton as illustrative commercial
  total capital expenditure; the higher BTB-plus-DOE result
  should therefore be treated as an exploratory cost scenario.
