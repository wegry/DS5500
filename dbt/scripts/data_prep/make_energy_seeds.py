"""Rebuild the Cambium and AEO seeds for the energy scenarios from the raw downloads.

Reads the scenario sources in data/raw/ (see data/raw/SOURCES.md) and writes:
    seeds/cambium24_isone_aer.csv           ISO-NE average emission rate, all Cambium 2024 scenarios
    seeds/aeo2026_ne_commercial_prices.csv  AEO2026 New England commercial prices, all cases

seeds/berdo_projected_grid_factors.csv is typed from the BERDO Policies & Procedures PDF and
225 CMR 14.07, so it isn't generated here.

Run from dbt/:
    uv run python scripts/data_prep/make_energy_seeds.py
"""

from __future__ import annotations

import csv
import io
import json
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[2]
RAW = HERE.parent / "data" / "raw"
SEEDS = HERE / "seeds"

AEO_SERIES = {
    "Energy Prices: Commercial: Electricity": "electricity",
    "Energy Prices: Commercial: Natural Gas": "natural_gas",
    "Energy Prices: Commercial: Distillate Fuel Oil": "distillate",
}


def cambium() -> None:
    with zipfile.ZipFile(RAW / "cambium" / "Cambium24_allScenarios_annual_gea.zip") as z:
        name = next(n for n in z.namelist() if n.endswith(".csv"))
        lines = z.read(name).decode().splitlines()
    # five preamble rows (project info, documentation link, category, units) before the header
    rows = csv.DictReader(io.StringIO("\n".join(lines[5:])))
    out = sorted(
        (r["scenario"], int(r["t"]), float(r["aer_load_co2e"])) for r in rows if r["gea"] == "ISONE"
    )
    with (SEEDS / "cambium24_isone_aer.csv").open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["cambium_scenario", "year", "aer_load_co2e_kg_per_mwh"])
        w.writerows(out)
    print(f"cambium24_isone_aer.csv: {len(out)} rows")


def aeo() -> None:
    out = []
    for f in sorted((RAW / "eia_aeo2026").glob("table3_new_england_*.json")):
        table = json.loads(f.read_text())["tabledata"]
        for row in table["rows"].values():
            fuel = AEO_SERIES.get(row.get("chart_name"))
            if not fuel:
                continue
            for case_id, series in row["data"].items():
                for year, value in series.items():
                    if year != "9999":  # 9999 is the 2025-2050 growth rate
                        out.append((case_id.split("-")[0], fuel, int(year), round(value, 4)))
    out.sort()
    with (SEEDS / "aeo2026_ne_commercial_prices.csv").open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["aeo_case", "fuel", "year", "usd2025_per_mmbtu"])
        w.writerows(out)
    print(f"aeo2026_ne_commercial_prices.csv: {len(out)} rows")


if __name__ == "__main__":
    cambium()
    aeo()
