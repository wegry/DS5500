import marimo

__generated_with = "0.25.1"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo
    import polars as pl
    from pathlib import Path

    return Path, mo, pl


@app.cell
def _(Path):
    DATA = Path(__file__).resolve().parent.parent / "data" / "raw" / "btb"
    BTB_XLSX = DATA / "btb2024_commercial_dataset_and_sources.xlsx"
    data_comstock = Path(__file__).resolve().parent.parent / "data" / "raw" / "comstock"
    sorted(file.name for file in DATA.glob("*.xlsx"))
    return DATA, data_comstock


@app.cell
def _(DATA, pl):
    BTB_XLSX = DATA / "btb2024_commercial_dataset_and_sources.xlsx"

    btb = pl.read_excel(
        BTB_XLSX,
        sheet_id=1,
        has_header=True,
        infer_schema_length=0)

    btb.head(8)
    return (btb,)


@app.cell
def _(btb):
    print(f"Rows: {btb.height}, columns: {btb.width}")
    print("\n".join(btb.columns))
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    From dictionary(https://docs.nlr.gov/docs/fy26osti/93343.pdf) p.18: Typical Retrofit Installed Cost (low, mid, high estimates) - equipment + installation. Won't need to add them up separately.
    """)
    return


@app.cell
def _(btb):
    btb.select(
        "End Use Category",
        "Component",
        "Technology/Measure").unique().sort("End Use Category", "Component", "Technology/Measure")
    return


@app.cell
def _(data_comstock):
    # Comstock packages 
    import json
    upgrade_lookup = json.loads(
        (data_comstock / "upgrades_lookup.json").read_text(encoding="utf-8-sig"))
    for _upgrade_id in range(54, 66):
        print(f"{_upgrade_id}: {upgrade_lookup.get(str(_upgrade_id), 'Not listed')}")
    return (upgrade_lookup,)


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    **Update in packages from 2025 Release 3** https://natlabrockies.github.io/ComStock.github.io/docs/resources/explanations/2025_release_3_packages_known_issue.html?utm_source=chatgpt.comIn ComStock 2025 Release 3, the results and upgrade names for upgrade packages pkg_0003 and pkg_0004 are reversed. This mixup has been addressed in the OEDI upgrades_lookup.json and measure_name_crosswalk.csv files, but the mislabeling remains in the metadata and annual results files on OEDI, and on the Data Viewer.
    """)
    return


@app.cell(hide_code=True)
def _(upgrade_lookup):
    # Updated packages 54 and 57
    corrected_lookup = upgrade_lookup.copy() 
    corrected_lookup["56"] = "Package 3, Package 1 + Package 2"
    corrected_lookup["57"] = "Package 4, Package 2 with Standard Performance HP RTU"
    for _upgrade_id in range(54, 66):
        print(f"{_upgrade_id}: {corrected_lookup[str(_upgrade_id)]}")
    return


@app.cell
def _(btb, pl):
    btb_cost_coverage = btb.group_by(
        "End Use Category",
        "Component").agg(
        pl.col("Technology/Measure ID")
            .n_unique()
            .alias("technologies"),
        pl.col("Typical Retrofit Installed Cost ($2023) - Mid")
            .cast(pl.Float64, strict=False)
            .null_count()
            .alias("missing_or_nonnumeric_costs"),
        pl.col("Regression Output Units")
            .drop_nulls()
            .unique()
            .alias("reported_price_units")).sort("End Use Category", "Component")

    btb_cost_coverage
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Initial comparison of ComStock packages and BTB

    We compared the package names with BTB technologies and read some
    installation notes. These are initial observations; exact matches
    and complete package costs still need checking.

    | ID | Package | What we found so far |
    |---|---|---|
    | 54 | Wall insulation + roof insulation + windows | BTB lists these technologies. We still need to check the insulation and window types. |
    | 55 | LEDs + variable-speed heat pumps | BTB lists LEDs and heat pumps. We need to check whether the heat-pump types match. |
    | 56 | Insulation + windows + LEDs + heat pumps | BTB lists the main technologies. The exact equipment and materials still need matching. |
    | 57 | LEDs + standard-performance heat pumps | BTB lists LEDs and standard RTU heat pumps. The heat-pump boiler option still needs checking. |
    | 58 | Heat pumps + ventilation improvements | Several technologies appear in BTB, but we have not identified a separate economizer cost. |
    | 59 | Ground-source heat pumps | BTB lists the equipment, but its cost excludes the ground heat exchanger. |
    | 60 | Controls to reduce demand during grid peaks | BTB lists building automation systems. We have not confirmed whether they cover the controls this package needs. |
    | 61 | Demand controls + solar panels | The controls need checking, and we have not identified solar-panel costs in this file. |
    | 62 | Controls to reduce each building’s peak demand | Building automation may be relevant, but an exact cost match has not been confirmed. |
    | 63 | Insulation + windows + ground-source heat pumps | BTB lists the main technologies, but the ground heat exchanger cost is still needed. |
    | 64 | Insulation + windows + ground-source heat pumps + LEDs | BTB lists the main technologies, but the ground heat exchanger cost is still needed. |
    | 65 | Solar panels + roof insulation | BTB lists roof insulation. We have not identified solar-panel costs in this file. |

    We checked that the mid-range installed-cost field contains numeric
    values without missing entries.
    """)
    return


@app.cell
def _(btb, pl):
    # Package 54 check
    package54_candidates = btb.filter(
        pl.col("Component").is_in([
            "Wall Insulation",
            "Roof Insulation",
            "Fenestration"])
    ).select(
        "Technology/Measure ID",
        "Component",
        "Technology/Measure",
        "Regression metric 1 - Metric",
        "Regression metric 1 - Unit",
        "Regression metric 1 - Lower Bound",
        "Regression metric 1 - Upper Bound",
        "Regression metric 2 - Metric",
        "Regression metric 2 - Unit",
        "Regression metric 2 - Lower Bound",
        "Regression metric 2 - Upper Bound",
        "Notes").unique().sort("Component", "Technology/Measure")

    for _candidate in package54_candidates.iter_rows(named=True):
        for _field, _value in _candidate.items():
            print(f"{_field}: {_value}")
        print()
    return


@app.cell
def _(data_comstock, pl):
    # Comstock climat zone, window size
    comstock_sample = pl.read_csv(
        data_comstock / "MA_G2500250_upgrade0.csv.gz",
        n_rows=5,
        infer_schema_length=0)

    matching_columns = [
        column for column in comstock_sample.columns
        if any(term in column.lower() for term in [
            "climate_zone",
            "ext_wall_area",
            "ext_roof_area",
            "ext_window_area"])]

    comstock_sample.select(matching_columns)
    return (comstock_sample,)


@app.cell
def _(btb, pl):
    btb_component_review = (
        btb.filter(
            pl.col("Year").cast(pl.Int64, strict=False) == 2023,
            pl.col("Scenario") == "Reference").select(
            pl.col("Technology/Measure ID").alias("BTB ID"),
            "Component","Technology/Measure",
            pl.col("Typical Retrofit Installed Cost ($2023) - Mid").cast(pl.Float64, strict=False).alias("Mid retrofit cost ($2023)"),
            pl.format("{} ({})",
                pl.col("Regression metric 1 - Metric"),
                pl.col("Regression metric 1 - Unit")).alias("Required input 1"),
            pl.format("{} ({})",
                pl.col("Regression metric 2 - Metric"),
                pl.col("Regression metric 2 - Unit") ).alias("Required input 2"),
            pl.col("Regression Output Units").alias("Regression price units"),
            pl.col("Typical unit multiplier").alias("Typical quantity"),
            pl.col("Typical unit multiplier units name").alias("Quantity units"),
            "Notes").unique().sort("Component", "Technology/Measure", "BTB ID"))

    btb_component_review
    return (btb_component_review,)


@app.cell
def _(data_comstock, pl):
    comstock_check_rows = []

    for _package_id in range(54, 66):
        _path = data_comstock / f"MA_G2500250_upgrade{_package_id}.csv.gz"
        if not _path.exists():
            print(f"Package {_package_id}: file not found")
            continue

        _header = pl.read_csv(_path, n_rows=0, infer_schema_length=0).columns
        _fields = [
            _column
            for _column in _header
            if _column.startswith("out.params.")
            and any(
                _term in _column.lower()
                for _term in [
                    "ext_wall_area", "ext_roof_area", "ext_window_area",
                    "capacity", "ieer", "cop", "lighting",
                    "airflow", "air_flow", "ventilation",
                    "economizer", "photovoltaic", "pv"])]

        if not _fields:
            print(f"Package {_package_id}: no matching fields found")
            continue

        _values = pl.read_csv(_path, columns=_fields, infer_schema_length=0)

        for _field in _fields:
            _numbers = _values[_field].cast(pl.Float64, strict=False)

            comstock_check_rows.append({
                "Package": _package_id,
                "Field": _field,
                "Total records": len(_numbers),
                "Numeric records": int(_numbers.is_not_null().sum()),
                "Positive records": int((_numbers > 0).sum())})

    comstock_input_checks = (pl.DataFrame(comstock_check_rows).sort("Package", "Field"))

    comstock_input_checks
    return (comstock_input_checks,)


@app.cell
def _(comstock_input_checks, pl):
    comstock_input_matrix = (
        comstock_input_checks
        .with_columns(
            (100 * pl.col("Positive records") / pl.col("Total records")).round(1).alias("Positive records (%)"))
        .pivot(
            on="Package",
            index="Field",
            values="Positive records (%)").sort("Field"))

    comstock_input_matrix
    return (comstock_input_matrix,)


@app.cell
def _(mo):
    component_links = {
        "Insulation and windows": (
            ["Wall Insulation", "Roof Insulation", "Fenestration"],
            "ext_wall_area|ext_roof_area|ext_window_area",
            [54, 56, 63, 64, 65],
            "Check insulation and window specifications. Interior wall "
            "insulation and window film are not direct matches for Package 54."),
        "LED lighting": (
            ["LED"],
            "interior_lighting|exterior_lighting",
            [55, 56, 57, 64],
            "Lighting power is not a fixture count. Check fixture types, "
            "quantities, lumens, and efficacy."),
        "RTU and hydronic heat pumps": (
            ["RTU Heat Pump", "Hydronic Heat Pump"],
            "dx_cooling_capacity_tons|dx_cooling_design_ieer|"
            "ww_hp_heating_capacity|ww_hp_heating.*cop",
            [55, 56, 57, 58],
            "Check equipment equivalence, capacity basis, and efficiency. "
            "Hydronic heating capacity does not directly establish the "
            "cooling capacity required by BTB."),
        "Ventilation and economizer": (
            ["Demand Controlled Ventilation", "Energy Recovery"],
            "outdoor_air_flow|economizer",
            [58],
            "Check airflow units and energy-recovery efficiency. No dedicated "
            "economizer cost entry was identified. Numeric checks cannot "
            "evaluate a text field such as economizer_control_type."),
        "Ground-source heat pumps": (
            ["Ground Source Heat Pump", "Water Source Heat Pump"],
            "wa_hp|ww_hp",
            [59, 63, 64],
            "Check which equipment entry applies. The ground-source entry "
            "explicitly excludes the ground heat exchanger."),
        "Demand controls — BAS proxy": (
            ["Building Automation System"],
            "thermostat|lighting.*control|demand|load_shed",
            [60, 61, 62],
            "BAS is a possible proxy, not a confirmed match. Our earlier "
            "field search did not cover all controls information."),
        "Solar PV": (
            ["Photovoltaic", "Photovoltaics", "Solar PV"],
            "pv_system_size",
            [61, 65],
            "No dedicated PV entry was identified in the BTB table. "
            "A solar water heater is not a photovoltaic system.")}
    component_picker = mo.ui.dropdown(
        options=list(component_links),
        value="Insulation and windows",
        label="Choose a component group")

    component_picker
    return component_links, component_picker


@app.cell
def _(
    btb_component_review,
    component_links,
    component_picker,
    comstock_input_checks,
    comstock_input_matrix,
    mo,
    pl,
):
    _components, _pattern, _packages, _question = (component_links[component_picker.value])
    _btb_rows = btb_component_review.filter(pl.col("Component").is_in(_components))
    _package_columns = [str(_package) for _package in _packages if str(_package) in comstock_input_matrix.columns]
    _missing_packages = [_package for _package in _packages if str(_package) not in comstock_input_matrix.columns]
    _matrix_rows = (comstock_input_matrix.filter(pl.col("Field").str.contains(_pattern)).select("Field", *_package_columns))
    _count_rows = comstock_input_checks.filter(pl.col("Package").is_in(_packages),pl.col("Field").str.contains(_pattern))

    mo.vstack([
        f"Relevant packages: {_packages}",
        f"Review question: {_question}",
        f"Packages without results: {_missing_packages}",
        "BTB cost entries, required inputs, and notes:",
        mo.ui.table(_btb_rows),
        "ComStock records with positive values (%):",
        (mo.ui.table(_matrix_rows)
         if _matrix_rows.height > 0
         else "No matching fields in our exported checks."),
        "Exact ComStock counts:",
        mo.ui.table(_count_rows)])
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Conclusion

    BTB can help us estimate retrofit costs, but it does not cover every ComStock package completely.
    Packages 54–57 look like the best candidates so far. They include insulation, windows, LEDs, and heat pumps that have potential cost matches in BTB. We still need assumptions about equipment specifications and quantities.
    Other packages have larger gaps. Ground-source heat pump costs exclude the ground heat exchanger, and we have not found direct cost matches for solar PV or the specific demand controls.
    """)
    return


@app.cell
def _(btb_component_review, comstock_sample, pl):
    # insulation cost test check
    _wall_btb = (
        btb_component_review.filter(pl.col("BTB ID").cast(pl.String) == "92").row(0, named=True))
    _wall_rate = (float(_wall_btb["Mid retrofit cost ($2023)"]) / float(_wall_btb["Typical quantity"]))
    _wall_area_m2 = float(comstock_sample["out.params.ext_wall_area..m2"][0])
    _wall_area_ft2 = _wall_area_m2 / 0.09290304
    wall_cost_example = pl.DataFrame({
        "Wall area (m²)": [round(_wall_area_m2, 2)],
        "Wall area (ft²)": [round(_wall_area_ft2, 2)],
        "Installed cost ($2023/ft²)": [round(_wall_rate, 4)],
        "Estimated installed cost ($2023)": [round(_wall_area_ft2 * _wall_rate, 2)]})

    wall_cost_example
    return


@app.cell
def _(btb_component_review, comstock_sample, pl):
    # roof cost test check
    _roof_btb = (btb_component_review.filter(pl.col("BTB ID").cast(pl.String) == "93").row(0, named=True))
    _roof_rate = (
        float(_roof_btb["Mid retrofit cost ($2023)"])
        / float(_roof_btb["Typical quantity"]))
    _roof_area_m2 = float(comstock_sample["out.params.ext_roof_area..m2"][0])
    _roof_area_ft2 = _roof_area_m2 / 0.09290304
    roof_cost_example = pl.DataFrame({
        "Roof area (m²)": [round(_roof_area_m2, 2)],
        "Roof area (ft²)": [round(_roof_area_ft2, 2)],
        "Installed cost ($2023/ft²)": [round(_roof_rate, 4)],
        "Estimated installed cost ($2023)": [
            round(_roof_area_ft2 * _roof_rate, 2)]})

    roof_cost_example
    return


@app.cell
def _(btb_component_review, comstock_sample, pl):
    # windows cost test check
    _window_area_ft2 = (
        float(comstock_sample["out.params.ext_window_area..m2"][0])
        / 0.09290304)
    window_cost_examples = (
        btb_component_review.filter(
            pl.col("Component") == "Fenestration", pl.col("Technology/Measure").str.contains("Double-Pane|Triple-Pane")).with_columns(
            (pl.col("Mid retrofit cost ($2023)").cast(pl.Float64)/ pl.col("Typical quantity").cast(pl.Float64)).alias("Installed cost ($2023/ft²)"), pl.lit(_window_area_ft2).alias("Window area (ft²)") ).with_columns(
            (pl.col("Installed cost ($2023/ft²)")* pl.col("Window area (ft²)")).alias("Estimated installed cost ($2023)")).select(
            "BTB ID",
            "Technology/Measure",
            "Window area (ft²)",
            "Installed cost ($2023/ft²)",
            "Estimated installed cost ($2023)").sort("Technology/Measure"))

    window_cost_examples
    return


@app.cell
def _(data_comstock, pl):
    led_upgrade_sample = pl.read_csv(
        data_comstock / "MA_G2500250_upgrade57.csv.gz",
        n_rows=1,
        infer_schema_length=0)

    for _column in led_upgrade_sample.columns:
        if (_column.startswith(("in.", "out.params.")) and any(_term in _column.lower()
                for _term in ["lighting", "fixture", "lamp","lumen", "floor_area", "sqft"])):
            print(f"{_column}: {led_upgrade_sample[_column][0]}")
    return (led_upgrade_sample,)


@app.cell
def _(btb, led_upgrade_sample, pl):
    # LED test
    import math as _math

    _led_btb = (
        btb.filter(
            pl.col("Technology/Measure ID").cast(pl.String) == "12",
            pl.col("Year").cast(pl.Int64, strict=False) == 2023,
            pl.col("Scenario") == "Reference").row(0, named=True))
    _lighting_watts = (
        float(led_upgrade_sample["in.sqft..ft2"][0])
        * float(led_upgrade_sample["out.params.interior_lighting_power_density..w_per_ft2"][0]))
    _fixture_watts = (float(_led_btb["Regression metric 1 - Typical"])/ float(_led_btb["Regression metric 2 - Typical"]))
    _fixture_count = _math.ceil(_lighting_watts / _fixture_watts)
    _fixture_cost = float(_led_btb["Typical Retrofit Installed Cost ($2023) - Mid"])
    led_cost_example = pl.DataFrame({
        "Interior lighting power (W)": [round(_lighting_watts, 2)],
        "Assumed fixture power (W)": [round(_fixture_watts, 2)],
        "Estimated fixtures": [_fixture_count],
        "Installed cost per fixture ($2023)": [round(_fixture_cost, 2)],
        "Estimated installed cost ($2023)": [
            round(_fixture_count * _fixture_cost, 2)]})

    led_cost_example
    return


@app.cell
def _(btb, led_upgrade_sample, pl):
    # Heat pump test
    _hp_btb = (
        btb.filter(
            pl.col("Technology/Measure ID").cast(pl.String) == "1",
            pl.col("Year").cast(pl.Int64, strict=False) == 2023,
            pl.col("Scenario") == "Reference").row(0, named=True))
    _hp_reference_tons = float(_hp_btb["Regression metric 1 - Typical"])
    _hp_reference_cost = float(_hp_btb["Typical Retrofit Installed Cost ($2023) - Mid"])
    _hp_example_tons = float(led_upgrade_sample["out.params.dx_cooling_capacity_tons..tons"][0])
    _hp_cost_per_ton = _hp_reference_cost / _hp_reference_tons
    heat_pump_cost_example = pl.DataFrame({
        "ComStock cooling capacity (tons)": [round(_hp_example_tons, 2)],
        "BTB reference capacity (tons)": [_hp_reference_tons],
        "BTB reference installed cost ($2023)": [round(_hp_reference_cost, 2)],
        "Assumed installed cost ($2023/ton)": [round(_hp_cost_per_ton, 2)],
        "Estimated installed cost ($2023)": [round(_hp_example_tons * _hp_cost_per_ton, 2)]})

    heat_pump_cost_example
    return


@app.cell(hide_code=True)
def _(mo):
    mo.md(r"""
    ### Example installation cost estimates

    All costs are expressed in 2023 dollars.

    | Upgrade | Costing method | Example installed cost | Main assumptions |
    |---|---|---:|---|
    | Exterior wall insulation | Wall area × BTB reference cost per ft² | $19,705 | Entire wall area is treated; BTB insulation is a suitable cost proxy. |
    | Roof insulation | Roof area × BTB reference cost per ft² | $2,383 | Entire roof is treated at BTB’s reference insulation specification. |
    | Replacement windows | Window area × reference cost per ft² | $3,860–$9,989 | All windows are replaced; cost varies across the four window types examined. |
    | LED lighting | Estimated fixture count × installed cost per fixture | $5,147 | All interior lights are replaced with the assumed 44 W Troffer & Panel fixtures. |
    | Standard rooftop heat pump | Cooling capacity × reference installed cost per ton | $22,483 | Cost scales proportionally with capacity; BTB’s reference efficiency is used. Unit-count differences and roof curb adapters are not included. |

    ### Conclusion

    It shows possible costing methods for five upgrade types using BTB prices and ComStock quantities. These are illustrative estimates based on stated assumptions. They do not yet confirm exact equipment matches, upgrade applicability, or costs for our university buildings.
    """)
    return


if __name__ == "__main__":
    app.run()
