-- EN 15459 global cost of each var("decision_period_start") option in berdo_decision_options,
-- as a present value over var("global_cost_years") years from var("horizon_start") (2027),
-- so it includes the ACPs of the rest of the 2025-2029 period, in var("dollar_year") dollars:
--   installed cost + replacements - residual value      (per component, BTB lifetimes)
--   + sum over years t of (energy + O&M + emissions cost) / (1 + r)^t
-- Two perspectives, after the EU cost-optimal method (Delegated Regulation 244/2012):
-- financial pays BERDO Alternative Compliance Payments on emissions over each period's
-- standard at a private discount rate; societal prices all emissions at the social cost of
-- carbon at a low rate and leaves out ACPs, which are a transfer to the city.
-- Components are installed at the start and replaced at the end of each lifetime; the last
-- one is credited its straight-line remaining value at the horizon. Running costs fall at
-- the end of each year. Options that keep the existing heating and cooling equipment
-- (replaces_hvac false) replace it like-for-like (int_berdo_existing_hvac) after its
-- remaining_years and then every lifetime, credited its remaining value at the horizon
-- (existing_hvac_pv_*); the others replace it at the start with their own equipment.
-- Energy scenarios (energy_scenarios seed) move three things year by year, each as an index
-- relative to 2025, the BERDO data year; energy use itself stays at the BERDO year's level:
--   * Compliance (owner): the electricity part of a building's BERDO emissions follows the
--     City's projected grid factor x (1 - RPS Class I share) (berdo_projected_grid_factors,
--     BERDO Policies & Procedures Appendix B and 225 CMR 14.07). The index assumes a
--     building's BCCE/REC share stays the same fraction.
--   * Climate damage (society): the electricity part follows NLR Cambium 2024's ISO-NE
--     average emission rate for end-use load (cambium24_isone_aer, 5-year points
--     interpolated linearly), since the real grid, not BERDO's accounting, does the damage.
--   * Energy bills: electricity and district cooling follow AEO2026 New England commercial
--     electricity; gas and district steam follow commercial natural gas; oil follows
--     distillate (aeo2026_ne_commercial_prices). The low/mid/high price cases set the 2025
--     level; the AEO case sets the path from there.
-- Scenario 'frozen' holds all three at 2025 and reproduces the original model. Whether an
-- option meets the standard (meets_standard_at_start) is checked in var("decision_period_start")
-- (2030), the first year of the 3.2 kg/sq ft office standard, under each scenario.
-- Grain: BERDO building x option x perspective x energy price case x energy scenario.
{{ berdo_global_cost(
    options=ref('berdo_decision_options'),
    scenarios=ref('berdo_upgrade_scenarios'),
    package_costs=ref('int_berdo_package_costs'),
    existing_hvac=ref('int_berdo_existing_hvac')
) }}
