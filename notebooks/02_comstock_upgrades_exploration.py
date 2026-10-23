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
    ### 1. Setup
    """)
    return


@app.cell
def _():
    import json
    from pathlib import Path
    import matplotlib.pyplot as plt

    print("Working directory:", Path.cwd())
    return Path, json, plt


@app.cell
def _(Path):
    comstock_dir = Path.cwd() / "data" / "raw" / "comstock"
    lookup_path = comstock_dir / "upgrades_lookup.json"

    print("Lookup exists:", lookup_path.is_file())
    return comstock_dir, lookup_path


@app.cell
def _(json, lookup_path):
    with open(lookup_path, "r", encoding="utf-8") as file:
        upgrade_lookup = json.load(file)

    print("Data type:", type(upgrade_lookup))
    print("Number of top-level entries:", len(upgrade_lookup))
    print("\nPreview:")
    print(json.dumps(upgrade_lookup, indent=2)[:2000])
    return (upgrade_lookup,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
 
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 2. Upgrade Scenario Inventory
    """)
    return


@app.cell
def _(upgrade_lookup):
    import pandas as pd

    upgrade_inventory = pd.DataFrame([{"upgrade_id": int(key), "description": value}
                                      for key, value in upgrade_lookup.items()]).sort_values("upgrade_id").reset_index(drop=True)

    print("Total scenarios:", len(upgrade_inventory))
    print("Upgrade scenarios excluding baseline:", (upgrade_inventory["upgrade_id"] != 0).sum())

    upgrade_inventory
    return pd, upgrade_inventory


@app.cell
def _(upgrade_inventory):
    for row in upgrade_inventory.itertuples(index=False):
        print(f"{row.upgrade_id}: {row.description}")
    return


@app.cell
def _(upgrade_inventory):
    # Upgrade Classification
    def classify_upgrade(upgrade_id):
        if upgrade_id == 0:
            return "Baseline"
        elif 1 <= upgrade_id <= 31:
            return "HVAC and heating"
        elif 32 <= upgrade_id <= 42:
            return "Demand flexibility"
        elif 43 <= upgrade_id <= 45:
            return "Lighting and kitchen"
        elif 46 <= upgrade_id <= 47:
            return "Solar and storage"
        elif 48 <= upgrade_id <= 53:
            return "Building envelope"
        elif 54 <= upgrade_id <= 65:
            return "Retrofit packages"
        return "Other"


    upgrade_inventory["category"] = upgrade_inventory["upgrade_id"].apply(classify_upgrade)

    print("Scenarios by category:")
    print(upgrade_inventory["category"].value_counts())

    upgrade_inventory
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 3. Upgrade Datasets Structure
    """)
    return


@app.cell
def _(Path):
    import sys
    import importlib

    sys.path.insert(0, str(Path.cwd() / "src"))

    import comstock
    importlib.reload(comstock)

    from comstock import load_comstock, validate_upgrade, validate_all_upgrades

    return comstock, load_comstock, validate_upgrade


@app.cell
def _(comstock_dir, load_comstock):
    upgrade43_path = comstock_dir / "MA_G2500250_upgrade43.csv.gz"
    upgrade43= load_comstock(upgrade43_path)

    print("Rows:", upgrade43.shape[0])
    print("Columns:", upgrade43.shape[1])
    print("Unique building IDs:", upgrade43["bldg_id"].nunique())
    return (upgrade43,)


@app.cell
def _(comstock_dir, load_comstock, pd, upgrade43):
    # Baseline - Upgrade Compatability
    baseline = load_comstock(comstock_dir / "MA_G2500250_upgrade0.csv.gz")

    match_keys = ["bldg_id", "in.nhgis_tract_gisjoin"]

    baseline_keys = pd.MultiIndex.from_frame(baseline[match_keys])
    upgrade_keys = pd.MultiIndex.from_frame(upgrade43[match_keys])

    print("Same columns:", set(baseline.columns) == set(upgrade43.columns))

    print("\nDuplicate baseline keys:", baseline.duplicated(match_keys).sum())
    print("Duplicate upgrade keys:", upgrade43.duplicated(match_keys).sum())

    print("\nBaseline keys missing from upgrade:",
          len(baseline_keys.difference(upgrade_keys)))
    print("Upgrade keys missing from baseline:",
          len(upgrade_keys.difference(baseline_keys)))

    print("\nGeneral applicability:")
    print(upgrade43["applicability"].value_counts(dropna=False))

    print("\nLED applicability:")
    print(upgrade43["applicability.light_led"].value_counts(dropna=False))

    print("\nSimulation status:")
    print(upgrade43["completed_status"].value_counts(dropna=False))
    return (baseline,)


@app.cell
def _(upgrade43):
    # Applicability Verification
    print("General and LED applicability agree:",
          upgrade43["applicability"].equals(upgrade43["applicability.light_led"]))

    print("Applicability and success status agree:",
          (upgrade43["applicability"] ==
           upgrade43["completed_status"].eq("Success")).all())

    print("Unique applicable building IDs:",
          upgrade43.loc[upgrade43["applicability"], "bldg_id"].nunique())
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    Upgrade 43 (LED Lighting) has the same structure as the baseline, with 16,076 records and 1,347 columns. So all records can be matched using the building ID and census tract with no duplicates or missing matches. The LED upgrade is applicable to 10,945 records. The remaining 5,131 records are not applicable. We also confirmed that all applicable records have a successful simulation status, while non-applicable records are marked as invalid.

    Conclusion: Two datasets can be matched directly for baseline-to-upgrade comparisons. Energy and emissions savings will be calculated for applicable records with successful simulations. Repeated building IDs and geographic weights must be accounted for when interpreting or aggregating the results.
    """)
    return


@app.cell
def _(baseline, upgrade43, validate_upgrade):
    # Upgrade Validation
    validation43 = validate_upgrade(baseline, upgrade43, measure_flag="applicability.light_led")

    validation43
    return


@app.cell
def _(baseline):
    # Energy - Emission Comparison
    metric_columns = [
        col for col in baseline.columns
        if "site_energy" in col
        or ("emissions" in col and ("egrid" in col or "cambium" in col))]

    print(*metric_columns, sep="\n")
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ###
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 4. Validation Across All Upgrades
    """)
    return


@app.cell
def _():
    base_url = (
        "https://oedi-data-lake.s3.amazonaws.com/"
        "nrel-pds-building-stock/end-use-load-profiles-for-us-building-stock/"
        "2025/comstock_amy2018_release_3/metadata_and_annual_results/"
        "by_state_and_county/full/csv/state=MA/county=G2500250"
    )
    return (base_url,)


@app.cell
def _(base_url, baseline, comstock, comstock_dir):
    # Test 1st upgrade
    test1 = comstock.validate_single_upgrade(
        1,
        baseline[[
            "bldg_id",
            "in.nhgis_tract_gisjoin",
            "applicability",
            "completed_status"
        ]],
        comstock_dir,
        base_url
    )

    test1
    return


@app.cell
def _(base_url, baseline, comstock, comstock_dir):
    # Validate all upgrades
    all_validation = comstock.validate_all_upgrades(
        baseline,
        comstock_dir,
        base_url
    )

    all_validation
    return (all_validation,)


@app.cell
def _(all_validation):
    print("Upgrades checked:", len(all_validation))
    print("Errors:", all_validation["error"].notna().sum())
    print("Unmatched records:", all_validation["unmatched_baseline_keys"].sum())
    print("Applicability matches success:",
          all_validation["applicability_matches_success"].all())
    return


@app.cell
def _(Path, all_validation):
    results_dir = Path.cwd() / "results" / "comstock"
    results_dir.mkdir(parents=True, exist_ok=True)

    all_validation.to_csv(results_dir / "upgrade_validation_summary.csv", index=False)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### 5. Summaries
    """)
    return


@app.cell
def _(all_validation, baseline, pd):
    validation_summary = pd.DataFrame({
        "Check": [
            "Upgrades validated",
            "Processing errors",
            "Column structure matches",
            "Duplicate baseline keys",
            "Duplicate upgrade keys",
            "Unmatched baseline keys",
            "Unmatched upgrade keys",
            "Applicability matches success",
            "Fully applicable upgrades"],
        "Result": [
            len(all_validation),
            all_validation["error"].notna().sum(),
            all_validation["same_columns"].sum(),
            all_validation["duplicate_baseline_keys"].sum(),
            all_validation["duplicate_upgrade_keys"].sum(),
            all_validation["unmatched_baseline_keys"].sum(),
            all_validation["unmatched_upgrade_keys"].sum(),
            all_validation["applicability_matches_success"].sum(),
            (all_validation["applicable_records"] == len(baseline)).sum()]})

    validation_summary
    return


@app.cell
def _(all_validation, baseline, plt):
    fig, ax = plt.subplots(figsize=(14, 5))

    ax.bar(all_validation["upgrade_id"], all_validation["applicable_records"])
    ax.axhline(len(baseline), linestyle="--", label="Total baseline records")

    ax.set_xlabel("Upgrade ID")
    ax.set_ylabel("Applicable Records")
    ax.set_title("ComStock Upgrade Applicability Across 65 Scenarios")
    ax.set_xticks(range(1, 66, 4))
    ax.legend()

    plt.show()
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Findings
    """)
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    All 65 ComStock upgrade scenarios were successfully validated against the baseline. No duplicate or unmatched building–tract identifiers were found, and upgrade applicability was consistent with simulation success across all scenarios. Applicability varied considerably between upgrades, ranging from around 1000 to 16,000 records. This highlights the importance of checking whether an intervention is applicable to a simulated building before estimating its energy or emissions savings. These results establish a consistent structure for further baseline-to-upgrade comparisons. The validation covered identifiers, applicability, and completion status; it did not verify every energy and emissions field.
    """)
    return


if __name__ == "__main__":
    app.run()
