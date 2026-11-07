# Solar PV costing

ComStock upgrades:
- 46: rooftop solar PV
- 65: rooftop solar PV + roof insulation

PV capacity:
ComStock out.params.pv_system_size..kW,
treated as DC nameplate capacity.

Cost source:
U.S. Department of Energy (2025),
Solar Photovoltaic System Cost Benchmarks,
2025 Q1 commercial PV-only modeled market price.

https://www.energy.gov/cmei/systems/solar-photovoltaic-system-cost-benchmarks

Midpoint: $1.98/Wdc = $1,980/kWdc (2024 USD).
Low: $1,485/kWdc (-25%).
High: $2,475/kWdc (+25%).

Low/high range and 25-year lifetime are
modeling assumptions, not published uncertainty bounds.

Roof insulation for upgrade 65 uses BTB ID 93.

Limitations:
- Cost-year difference from BTB (2023 USD).
- Constant cost per kW assumes linear scaling.
- No incentives, roof structural assessment, or
  site-specific installation constraints.
- PV capacity is assumed to be DC-rated.
- PV output is reflected in ComStock's purchased
  electricity projections; no separate energy
  savings are added to avoid double counting.
