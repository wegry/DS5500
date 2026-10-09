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
    DATA = Path(__file__).resolve().parent.parent / "data" / "raw"
    BERDO_XLSX = DATA / "2026-berdo-data-disclosure-9.30.26.xlsx"
    return (BERDO_XLSX,)


@app.cell
def _(mo):
    mo.md(r"""
    # BERDO 2026 exploration

    Goal: find the university buildings in the BERDO disclosure.
    """)
    return


@app.cell
def _(BERDO_XLSX, pl):
    buildings = pl.read_excel(BERDO_XLSX, sheet_name="Buildings & Campuses")
    portfolios = pl.read_excel(BERDO_XLSX, sheet_name="Building Portfolios")
    return buildings, portfolios


@app.cell
def _(buildings, mo, portfolios):
    mo.md(f"""
    - Buildings & Campuses: **{buildings.height:,}** rows, {buildings.width} columns
    - Building Portfolios: **{portfolios.height}** rows
    """)
    return


@app.cell
def _(mo):
    mo.md(r"""
    ## Owners
    """)
    return


@app.cell
def _(buildings, pl):
    _owners = (
        buildings.group_by(pl.col("Parcel Owner Name").str.to_uppercase())
        .agg(
            pl.len().alias("buildings"),
            pl.col("Gross Floor Area (sq ft)").sum().alias("gfa_sqft"),
            pl.col("Largest Property Type").mode().first().alias("common_type"),
        )
        .sort("gfa_sqft", descending=True)
    )
    _owners
    return


@app.cell
def _(buildings, pl):
    _owners = (
        buildings.group_by("Parcel Owner Name")
        .agg(
            pl.len().alias("buildings"),
            pl.col("Gross Floor Area (sq ft)").sum().alias("gfa_sqft"),
            pl.col("Largest Property Type").mode().first().alias("common_type"),
        )
        .sort("gfa_sqft", descending=True)
    )
    _owners
    return


@app.cell
def _(mo):
    mo.md(r"""
    ## Property types
    """)
    return


@app.cell
def _(buildings, pl):
    buildings.group_by("Largest Property Type").agg(pl.len().alias("n")).sort(
        "n", descending=True
    )
    return


@app.cell
def _(portfolios):
    portfolios
    return


if __name__ == "__main__":
    app.run()
