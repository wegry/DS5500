# Reference data for the energy scenarios

Raw downloads behind the grid and price scenarios in `dbt/models/marts/berdo_global_cost.sql`.
All files were retrieved on **2026-11-07** and are stored unmodified in the subfolders of `data/raw/`
named below. These subfolders are tracked in git; the rest of `data/` is not. The dbt seeds
derived from them are listed under each source. `dbt/make_energy_seeds.py` rebuilds the
Cambium and AEO seeds from these files.

## NLR Cambium 2024: projected grid emissions (society's view)

- **File:** `cambium/Cambium24_allScenarios_annual_gea.zip`. Contains all 8 scenarios, annual
  resolution, GEA regions (2023$, weather year 2012).
- **Source:** NLR Scenario Viewer, project "Cambium 2024", Download tab, row "ALL / ALL /
  ALL / Annual / GEA Regions" (file id 69141). <https://scenarioviewer.nlr.gov/>
- **Citation:** Gagnon, P., Sanchez Perez, P. A., Florez, J., Morris, J., Llerena Velasquez, M.,
  and Eisenman, J. *Cambium 2024 Data.* National Renewable Energy Laboratory (now National
  Laboratory of the Rockies). Documentation: <https://www.nrel.gov/docs/fy25osti/93005.pdf>
- **Used:** region `ISONE`, metric `aer_load_co2e` (average CO2e emission rate of end-use
  load, kg/MWh), years 2025–2050 in 5-year steps. Seed: `dbt/seeds/cambium24_isone_aer.csv`.

## EIA Annual Energy Outlook 2026: energy price paths (bills)

- **Files:** `eia_aeo2026/table3_new_england_<case>.json`, one per case. These are Table 3
  ("Energy Prices by Sector and Source") for the New England census division, in 2025
  dollars per MMBtu, 2025–2050. They were fetched from the AEO data browser's data endpoint
  `https://www.eia.gov/outlooks/aeo/data/browser/data/index.php?studyID=AEO2026&tableID=3-AEO2026&caseID=<case>&regionID=1-1&freq=A&type=data`.
  - `suptab_3.1_new_england_prices_cb2026.xlsx` is the same table for the Counterfactual
    Baseline case, as a published XLSX:
    <https://www.eia.gov/outlooks/aeo/supplement/excel/suptab_3.1.xlsx>
  - `data_browser_config.json` holds EIA's case definitions.
  - `AEO2026_Narrative.pdf` holds the case descriptions. Per the narrative, the
    "Counterfactual Baseline" (formerly the Reference case) reflects laws and regulations as
    of December 2025. <https://www.eia.gov/outlooks/aeo/pdf/AEO_Narrative.pdf>
- **Citation:** U.S. Energy Information Administration, *Annual Energy Outlook 2026*, April 2026.
- **Used:** commercial electricity, natural gas and distillate fuel oil. Seed:
  `dbt/seeds/aeo2026_ne_commercial_prices.csv`.

## City of Boston: BERDO projected grid emissions factors (compliance)

- **File:** `berdo_policies/BERDO_Policies_and_Procedures_v4_2026-04-13.pdf`. BERDO Policies &
  Procedures, Version 4, adopted 2026-04-13 by the BERDO Review Board.
  <https://www.boston.gov/sites/default/files/file/2026/04/2026%20Draft%20Policies%20and%20Procedures%20Final.pdf>
- **Used:**
  - Appendix B, Projected Grid Emissions Factors, 2025–2050 (lb/MWh and kg/MWh), typed into
    `dbt/seeds/berdo_projected_grid_factors.csv`.
  - Section 5's electricity formula: emissions = use × (1 − RPS Class I) × grid factor.

## Massachusetts RPS Class I minimum standard (compliance)

- **File:** `ma_rps/225_CMR_14.07_cornell_lii.html`. This is 225 CMR 14.07(1) as published by
  Cornell LII. <https://www.law.cornell.edu/regulations/massachusetts/225-CMR-14-07>
- **Used:** the RPS Class I minimum percentage table, 27% in 2025 through 40% in 2030, plus
  1 percentage point a year after 2030 "unless modified by law". Typed into the
  `rps_class_i_pct` column of `dbt/seeds/berdo_projected_grid_factors.csv`.
- **Check:** 249 kg/MWh × (1 − 27%) = 181.8 kg/MWh, which is the largest electricity factor
  in the 2025 BERDO disclosure. Buildings below it buy extra renewables through Boston
  Community Choice Electricity.
