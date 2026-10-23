import marimo

__generated_with = "0.25.1"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo

    return (mo,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    # ComStock Baseline Data Exploration

    **Project:** Optimizing Corporate Decarbonization Investments: Which Projects to Fund, and in What Year

    ## Objective

    Examine the ComStock baseline dataset to understand its structure, building characteristics, geographic representation, energy consumption, and greenhouse gas emissions. The baseline will be a reference for estimating the impacts of retrofit scenarios and preparing inputs for multi-year decarbonization investment optimization.

    ## Dataset Scope

    - **Source:** ComStock, Open Energy Data Initiative (OEDI)
    - **Geographic coverage:** Suffolk County, Massachusetts
    - **Scenario:** Baseline (no additional ComStock upgrades applied)
    - **Target application:** Boston university and college buildings subject to BERDO

    Boston-specific filtering, upgrade comparisons, and integration with BERDO will be addressed in further analysis.

    ## Exploration Plan

    1. Load and inspect the baseline dataset.
    2. Examine dataset structure and repeated building identifiers.
    3. Inventory available columns and identify candidate variables.
    4. Investigate building characteristics and potential redundancy.
    5. Assess data quality and numerical consistency.
    6. Examine geographic representation and statistical weights.
    7. Identify and validate baseline energy consumption, EUI, and emissions metrics.

    The original dataset is preserved without filtering, cleaning, or removing records.
    """)
    return


@app.cell
def _():
    import pandas as pd
    import numpy as np
    from pathlib import Path

    return Path, np, pd


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## 1. Dataset Loading and Initial Inspection
    """)
    return


@app.cell
def _(Path):
    comstock_dir = Path("data/comstock")
    files = [p for p in comstock_dir.rglob("*") if p.is_file()]
    print("Files found:", len(files))
    for file in files[:20]:
        print(file)
    return (comstock_dir,)


@app.cell
def _(comstock_dir, pd):
    import tarfile

    baseline_path = comstock_dir / "MA_G2500250_upgrade0.csv.gz"

    with tarfile.open(baseline_path, "r:gz") as archive:
        csv_member = next(m for m in archive.getmembers() if m.name.endswith(".csv"))
        with archive.extractfile(csv_member) as csv_file:
            comstock = pd.read_csv(csv_file, low_memory=False)

    print("Rows:", comstock.shape[0])
    print("Columns:", comstock.shape[1])
    print("First columns:", comstock.columns[:5].tolist())

    comstock.head()
    return (comstock,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Dataset Overview

    The ComStock baseline dataset was obtained from the Open Energy Data Initiative (OEDI).

    - **File:** `MA_G2500250_upgrade0.csv.gz`
    - **Geographic coverage:** Suffolk County, Massachusetts (`G2500250`)
    - **Observations:** 16,076
    - **Variables:** 1,347
    - **Scenario:** Baseline (`upgrade = 0`)

    ### Baseline Scenario

    The baseline represents simulated building energy performance without upgrades applied. It will be a reference for evaluating energy savings and emissions reductions from retrofit scenarios.

    ### Geographic Scope

    The dataset covers Suffolk County, which includes Boston, Chelsea, Revere, and Winthrop. Since our project focuses on Boston university and college buildings subject to BERDO, we will need to determine how to isolate Boston-associated records using geographic identifiers.

    ### Data Loading

    The downloaded file contains a GZIP-compressed TAR archive. The CSV was extracted from the archive before loading it into pandas. The dataset was loaded successfully without modifying or filtering the original records.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## 2. Dataset Structure
    """)
    return


@app.cell
def _(comstock):
    print("Unique buildings:", comstock["bldg_id"].nunique())
    print("\nUpgrade scenarios:")
    print(comstock["upgrade"].value_counts(dropna=False))
    print("\nRows per building:")
    print(comstock.groupby("bldg_id").size().describe())
    print("\nExact duplicate rows:", comstock.duplicated().sum())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The dataset contains **16,076 records representing 1,719 unique building IDs**.

    ### Key Findings

    - All records belong to the baseline scenario (`upgrade = 0`).
    - Building IDs are not unique: each appears between 1 and 154 times.
    - The average number of records per building ID is 9.35, with a median of 4.
    - No exact duplicate rows were identified.

    Repeated building IDs might suggest that individual simulated building models may be associated with multiple geographic records and statistical weights.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## 3. Column Inspection and Feature Selection
    """)
    return


@app.cell
def _(comstock_dir, pd):
    dictionary_path = comstock_dir / "data_dictionary.tsv"
    data_dict = pd.read_csv(dictionary_path, sep="\t")

    print("Dictionary shape:", data_dict.shape)
    print("\nDictionary columns:", data_dict.columns.tolist())

    data_dict.head(10)
    return (data_dict,)


@app.cell
def _(comstock, data_dict):
    dataset_columns = set(comstock.columns)
    dictionary_columns = set(data_dict["field_name"])
    documented_columns = dataset_columns & dictionary_columns
    undocumented_columns = dataset_columns - dictionary_columns

    print("Dataset columns:", len(dataset_columns))
    print("Documented columns:", len(documented_columns))
    print("Undocumented columns:", len(undocumented_columns))

    print("\nColumns missing from dictionary:")
    print(sorted(undocumented_columns))
    return (undocumented_columns,)


@app.cell
def _(pd, undocumented_columns):
    missing_columns = pd.Series(sorted(undocumented_columns))
    missing_groups = missing_columns.str.split(".").str[0]

    print("Unmatched columns by prefix:")
    print(missing_groups.value_counts())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The baseline dataset contains 1,347 columns. The ComStock data dictionary includes 1,313 entries, but only 196 field names match the dataset exactly.

    ### Column Categories

    The unmatched columns are distributed as follows:

    | Prefix | Count | Description |
    |---|---:|---|
    | `out.` | 804 | Simulation outputs |
    | `calc.` | 298 | Calculated metrics |
    | `applicability.` | 38 | Upgrade applicability |
    | `in.` | 11 | Building and simulation inputs |

    Most unmatched columns are simulation outputs and calculated metrics. The lack of exact dictionary matches does not necessarily mean missing documentation, it might be due to the self-explanatory nature of certian columns.

    ### Feature Selection Strategy

    Instead of examining all 1,347 columns individually, we will select variables based on the project's requirements:

    - **Building characteristics:** building type, floor area, building agee, and energy systems for matching ComStock simulations to BERDO buildings.
    - **Geography:** census tract, county, and climate information for geographic matching.
    - **Energy performance:** energy consumption by fuel, total energy use, and energy use intensity.
    - **Emissions:** greenhouse gas emissions and relevant emissions calculation methods.
    - **Upgrade information:** scenario identifiers, applicability, and changes in energy performance.
    - **Statistical weights:** variables needed to understand building-stock representation.

    We will verify the definitions, units, and calculation methods of selected variables before using them in the analysis.
    **No columns have been removed at this stage.**
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 3.2. Upgrade Aplicability Inspection
    """)
    return


@app.cell
def _(comstock):
    applicability_columns = [col for col in comstock.columns if col == "applicability" or col.startswith("applicability.")]

    print("Number of applicability columns:", len(applicability_columns))
    print("\nApplicability columns:")
    print("\n".join(applicability_columns))
    return (applicability_columns,)


@app.cell
def _(applicability_columns, comstock, pd):
    applicability_profile = pd.DataFrame({
        "dtype": comstock[applicability_columns].dtypes.astype(str),
        "unique_values": comstock[applicability_columns].nunique(dropna=False),
        "missing_pct": comstock[applicability_columns].isna().mean() * 100})

    applicability_profile
    return


@app.cell
def _(applicability_columns, comstock):
    applicability_values = comstock[applicability_columns].iloc[0]

    print("Applicability flag values:")
    print(applicability_values.value_counts())
    print("\nFlags set to True:")
    print(applicability_values[applicability_values].index.tolist())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The baseline dataset contains 39 Boolean applicability columns with no missing values. The general `applicability` flag is `True` for all records, meanwhile all 38 measure-specific flags are `False`. Results are consistent with the baseline scenario, that contains no applied upgrades. BUt they do not tell us whether individual buildings are eligible for specific retrofit measures. Upgrade applicability will be investigated using the upgrade datasets.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## 4. Building Characteristics and Variable Selection

    ### 4.1. Candidate Variables
    """)
    return


@app.cell
def _(comstock):
    keywords = ["building_type", "sqft", "vintage", "year_built", "heating", "fuel", "stories"]

    building_columns = [col for col in comstock.columns if col.startswith("in.") and any(word in col.lower() for word in keywords)]

    print("Number of candidate columns:", len(building_columns))
    print("\n".join(building_columns))
    return (building_columns,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    We identified candidate building characteristics using keyword searches across ComStock input variables (`in.`). The variables cover building type, floor area, construction age, heating fuel, and number of stories. The results are displayed in the code output above.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.2. Missing Values and Cardinality
    """)
    return


app._unparsable_cell(
    r"""
    building_info = data_dict[data_dict["field_name"].isin(building_columns)]
        [["field_name", "field_description", "units"]]

    building_profile = pd.DataFrame({"unique_values": comstock[building_columns].nunique(), 
                                     "missing_pct": comstock[building_columns].isna().mean() * 100})

    print("Variable definitions:")
    print(building_info.to_string(index=False))

    print("\nVariable summary:")
    building_profile
    """,
    name="_"
)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    All nine candidate variables have 0% missing values. The number of distinct values varies substantially, reflecting categorical classifications and representative building characteristics.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.3. Redundant Variables
    """)
    return


@app.cell
def _(comstock):
    print("Story columns identical:")
    print(comstock["in.number_of_stories"].equals(comstock["in.number_stories"]))

    print("\nVintage and construction year:")
    print(comstock.groupby("in.vintage")["in.year_built"].agg(["min", "max", "nunique"]).sort_values("min"))
    return


app._unparsable_cell(
    r"""
    story_diff = comstock[comstock["in.number_of_stories"] != comstock["in.number_stories"]]

    print("Rows with different story counts:", len(story_diff))
    print("\nExamples:")story_diff[["bldg_id", "in.number_of_stories", "in.number_stories"]].head(10)
    """,
    name="_"
)


@app.cell
def _(comstock, pd):
    stories_numeric = pd.to_numeric(comstock["in.number_stories"], errors="coerce")
    print("Not converted values:", stories_numeric.isna().sum())
    story_mismatch = comstock["in.number_of_stories"] != stories_numeric
    print("Rows with different story counts:", story_mismatch.sum())

    comstock.loc[story_mismatch,["bldg_id", "in.number_of_stories", "in.number_stories"]].head()
    return (stories_numeric,)


@app.cell
def _(comstock, stories_numeric):
    print("Non-numeric story categories:")
    print(comstock.loc[stories_numeric.isna(), "in.number_stories"].value_counts())
    return


@app.cell
def _(comstock):
    comstock.groupby("in.number_stories")["in.number_of_stories"].agg(["count", "min", "max"]).loc[["15_25", "over_25"]]
    return


@app.cell
def _(building_columns, comstock):
    building_variation = (comstock.groupby("bldg_id")[building_columns].nunique(dropna=False))

    print("Building IDs with varying characteristics:")
    print((building_variation > 1).sum())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Construction year and vintage:** vintage is a categorical grouping of construction years. Both will be retained for now, with construction year providing greater detail.

    **Number of stories:** the numeric and categorical variables are consistent. Most records contain matching story counts, while 168 records use broader categories (`15_25` and `over_25`), corresponding to modeled counts of 20 and 30 stories.

    **Building type and heating fuel:** detailed building types and broader groups serve different purposes. HVAC heating fuel and water-heating fuel describe separate systems.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4.4. Consistency Across Building IDs

    All nine characteristics remain constant within each `bldg_id`, despite repeated records. Therefore, one record per building ID can be used for unweighted analysis of simulated building characteristics. The complete dataset will be preserved for geographic, statistical-weighting, and energy analyses.

    ### 4.5. Preliminary Conclusions

    The nine candidate variables are complete and internally consistent. Final selection will depend on their relevance to BERDO building matching and retrofit impact estimation.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## 5. Data Quality Assessment and Cleaning

    ### 5.1. Missing Values
    """)
    return


@app.cell
def _(comstock, pd):
    missing_summary = pd.DataFrame({"missing_count": comstock.isna().sum(), "missing_pct": comstock.isna().mean() * 100})

    print("Total columns:", comstock.shape[1])
    print("Columns with missing values:", (missing_summary["missing_count"] > 0).sum())
    print("Columns entirely missing:", (missing_summary["missing_pct"] == 100).sum())
    print("Columns with over 50% missing:", (missing_summary["missing_pct"] > 50).sum())

    missing_summary.sort_values("missing_pct", ascending=False).head(20)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Of the 1,347 columns, 1,288 have no missing values, while 59 contain at least one missing value. Only three columns exceed 50% missingness, including one completely missing column. The most affected variables describe specialized building or equipment characteristics. Their missingness may be related to applicability rather than data-quality issues. All nine previously identified building-characteristic candidates have complete data.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.2. Data Types
    """)
    return


@app.cell
def _(comstock):
    print("Data types:")
    print(comstock.dtypes.value_counts())
    print("\nText columns:")
    text_columns = comstock.select_dtypes(include=["object", "string"]).columns
    print("Number of text columns:", len(text_columns))
    print(text_columns.tolist())
    return


@app.cell
def _(comstock):
    object_columns = comstock.columns[comstock.dtypes == "object"]
    print("Object columns:", object_columns.tolist())

    for col in object_columns:
        print("\nColumn:", col)
        print(comstock[col].value_counts(dropna=False))
        print("\nNon-missing Python types:")
        print(comstock[col].dropna().map(type).value_counts())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    The dataset contains 1,216 numeric columns, 85 string columns, 45 Boolean columns, and one object column. The object column, `in.cejst_is_disadvantaged`, contains Boolean values and 2,538 missing entries. This explains its object data type rather than indicating inconsistent non-missing values.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5.3. Invalid Numerical Values Check
    """)
    return


@app.cell
def _(comstock, pd):
    numeric_columns = ["in.sqft..ft2", "in.number_of_stories", "in.year_built", "weight", "calc.weighted.sqft..ft2"]

    numeric_profile = pd.DataFrame({
        "min": comstock[numeric_columns].min(), 
        "max": comstock[numeric_columns].max(), 
        "zero_or_negative":(comstock[numeric_columns] <= 0).sum(), "missing": comstock[numeric_columns].isna().sum()})

    numeric_profile
    return


@app.cell
def _(comstock, np):
    expected_sqft = comstock["in.sqft..ft2"] * comstock["weight"]

    print("Rows with inconsistent weighted area:", (~np.isclose(comstock["calc.weighted.sqft..ft2"], expected_sqft)).sum())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    We examined floor area, number of stories, construction year, statistical weights, and weighted floor area. All five variables contain positive values, with no zero or negative observations. The weighted floor area calculation was also validated against building floor area multiplied by statistical weight. No inconsistencies were identified across the 16,076 records.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## 6. Geographic Coverage and Statistical Weights
    """)
    return


@app.cell
def _(comstock, pd):
    geo_columns = [
        "in.nhgis_county_gisjoin",
        "in.nhgis_tract_gisjoin",
        "in.as_simulated_nhgis_county_gisjoin",
        "in.as_simulated_nhgis_tract_gisjoin"]

    geo_summary = pd.DataFrame({"unique_values": comstock[geo_columns].nunique(), 
                                "missing_pct": comstock[geo_columns].isna().mean() * 100})

    print("Geographic identifiers:")
    print(geo_summary)
    print("\nCensus tracts per building:")
    print(comstock.groupby("bldg_id")["in.nhgis_tract_gisjoin"].nunique().describe())

    print("\nExample: Building 217")
    comstock.loc[comstock["bldg_id"] == 217, ["bldg_id", *geo_columns, "weight"]].head(10)
    return


@app.cell
def _(comstock):
    keys = ["bldg_id", "in.nhgis_tract_gisjoin"]

    print("Duplicate building-tract pairs:")
    print(comstock.duplicated(subset=keys).sum())

    sim_columns = [
        "in.as_simulated_nhgis_county_gisjoin",
        "in.as_simulated_nhgis_tract_gisjoin"]

    sim_variation = comstock.groupby("bldg_id")[sim_columns].nunique()

    print("\nBuilding IDs with varying simulation locations:")
    print((sim_variation > 1).sum())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Geographic Structure

    The baseline dataset covers one assigned county (Suffolk County) and 249 assigned census tracts. The underlying simulations span 22 counties and 1,019 census tracts. Building IDs are repeated across assigned census tracts, with a median of four tracts per building.

    **Key findings:**
    - Each building ID and assigned census tract combination is unique.
    - Each building ID has a consistent as-simulated location.
    - All examined geographic identifiers have complete data.

    The combination of `bldg_id` and assigned census tract is a candidate key for baseline-to-upgrade comparisons, subject to verification in the upgrade datasets.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## 7. Baseline Energy Performance
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 7.1. Examination of Selected Variables
    """)
    return


@app.cell
def _(comstock):
    energy_keywords = ["site_energy", "energy_use_intensity", "eui",
                       "emissions.total", "energy_consumption"]

    energy_columns = [
        col for col in comstock.columns
        if any(word in col.lower() for word in energy_keywords)
    ]

    print("Candidate energy and emissions columns:", len(energy_columns))
    #print("\n".join(energy_columns))
    return


@app.cell
def _(comstock):
    energy_cols = [col for col in comstock.columns if col.startswith("out.") 
                   and col.endswith(".total.energy_consumption..kwh")]
    eui_cols = [col for col in comstock.columns if col.startswith("out.site_energy.") 
                and col.endswith("total.energy_consumption_intensity..kwh_per_ft2")] # energy use intensity
    emissions_cols = [col for col in comstock.columns if col.startswith("calc.emissions.total_with_") 
                      and col.endswith("..co2e_kg")]

    performance_columns = energy_cols + eui_cols + emissions_cols

    print("Annual energy columns:", len(energy_cols))
    print("EUI columns:", len(eui_cols))
    print("Emissions columns:", len(emissions_cols))

    print("\nCandidate performance variables:")
    print("\n".join(performance_columns))
    return energy_cols, performance_columns


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 7.2. Energy and Emissions Data Quality Assessment
    """)
    return


@app.cell
def _(comstock, pd, performance_columns):
    performance_profile = pd.DataFrame({
        "missing_pct": comstock[performance_columns].isna().mean() * 100,
        "min": comstock[performance_columns].min(),
        "median": comstock[performance_columns].median(),
        "max": comstock[performance_columns].max()})

    performance_profile
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Key findings:**

    - All 10 displayed variables have 0% missing values and nonnegative minimum values. The remaining emissions variable still needs verification.
    - Electricity and total site energy consumption are positive across all records.
    - Several fuel categories have a median consumption of zero, suggesting that those energy sources are not used by most records.
    - `out.other_fuel.total.energy_consumption..kwh` contains only zeros.
    - Total site energy consumption ranges from approximately 18,111 to 35.1 million kWh.
    - Site energy use intensity (EUI) ranges from approximately 5.06 to 296.29 kWh/ft².
    - Large differences in energy consumption may reflect variation in building size and characteristics rather than data-quality errors.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 7.3. Energy Metrics Validation
    """)
    return


@app.cell
def _(comstock, energy_cols, np, performance_columns):
    fuel_columns = [col for col in energy_cols if not col.startswith("out.site_energy.")]
    fuel_total = comstock[fuel_columns].sum(axis=1)
    site_total = comstock["out.site_energy.total.energy_consumption..kwh"]
    eui_calculated = site_total / comstock["in.sqft..ft2"]
    eui_reported = comstock["out.site_energy.total.energy_consumption_intensity..kwh_per_ft2"]

    print("Missing performance values:")
    print(comstock[performance_columns].isna().sum())
    print("\nNegative performance values:")
    print((comstock[performance_columns] < 0).sum())
    print("\nSite energy mismatches:")
    print((~np.isclose(site_total, fuel_total, rtol=1e-5, atol=1)).sum())
    print("\nEUI mismatches:")
    print((~np.isclose(eui_reported, eui_calculated, rtol=1e-5, atol=0.01)).sum())
    return fuel_total, site_total


@app.cell
def _(comstock, fuel_total, np, site_total):
    energy_difference = site_total - fuel_total
    energy_mismatch = ~np.isclose(site_total, fuel_total, rtol=1e-5, atol=1)

    print("Energy differences for mismatched records:")
    print(energy_difference[energy_mismatch].describe())
    print("\nPositive differences:", (energy_difference[energy_mismatch] > 0).sum())
    print("Negative differences:", (energy_difference[energy_mismatch] < 0).sum())

    mismatch_examples = comstock.loc[energy_mismatch, 
        ["bldg_id", "out.electricity.pv.energy_consumption..kwh"]].copy()
    mismatch_examples["site_energy"] = site_total[energy_mismatch]
    mismatch_examples["fuel_total"] = fuel_total[energy_mismatch]
    mismatch_examples["difference"] = energy_difference[energy_mismatch]

    mismatch_examples.head(10)
    return (energy_difference,)


@app.cell
def _(energy_difference, site_total):
    relative_difference = energy_difference.abs() / site_total * 100

    print("Maximum relative difference (%):", relative_difference.max())
    print("Average relative difference (%):", relative_difference.mean())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    We validated total site energy consumption against the sum of individual fuel consumption values and recalculated energy use intensity (EUI) using building floor area.

    Key findings:

    - All EUI calculations match the reported values.
    - Site energy discrepancies occur in 732 records (4.55%).
    - The maximum relative discrepancy is 0.00676%, with an average of 0.000218% across all records.
    - These differences are negligible for the intended analysis and may result from rounding or numerical precision.
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ## 8. Baseline Exploration Summary

    The ComStock Suffolk County baseline dataset was examined to establish its structure, identify relevant variables, and assess data quality before comparing upgrade scenarios.

    **Key findings:**
    - The dataset contains 16,076 records representing 1,719 simulated building IDs.
    - Repeated building IDs correspond to distinct geographic assignments with statistical weights.
    - Building characteristics are consistent within each building ID.
    - A combination of building ID and assigned census tract uniquely identifies baseline records.
    - Candidate building characteristics and annual energy performance variables were identified.
    - The examined energy consumption, EUI, and emissions variables contain no missing or negative values.
    - Energy calculations are internally consistent within negligible numerical differences.

    **Remaining work:**

    Boston-specific geographic filtering, final variable selection, and preprocessing will be completed during data integration and baseline-to-upgrade comparison.
    """)
    return


if __name__ == "__main__":
    app.run()