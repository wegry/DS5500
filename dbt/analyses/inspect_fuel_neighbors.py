"""Read-only diagnostic of fuel representation among BERDO-ComStock neighbors.

Run from the dbt directory:
    python analyses/inspect_fuel_neighbors.py

Requires duckdb, pandas, matplotlib. Does not modify dbt models or DuckDB.
"""
from pathlib import Path
import duckdb
import pandas as pd
import matplotlib.pyplot as plt

DB = Path('ds5500.duckdb')
OUT = Path('analysis_outputs/fuel_neighbor_diagnostics')
CASES = [(105700, 'natural_gas'), (105612, 'natural_gas'), (106673, 'oil_propane')]
VALID_FUELS = {'electricity', 'natural_gas', 'oil_propane', 'district_heating', 'district_cooling'}

SQL = """
SELECT
    m.berdo_id,
    b.building_address,
    m.comstock_id,
    m.match_rank,
    m.distance,
    m.match_weight,
    m.size_gap,
    m.eui_gap,
    m.fuel_share_gap,
    m.stories_gap,
    CASE
        WHEN COALESCE(b.district_heating_kwh, 0) > 0
          OR COALESCE(b.district_cooling_kwh, 0) > 0
        THEN TRUE ELSE FALSE
    END AS berdo_uses_district,
    CASE
        WHEN COALESCE(c.district_heating_kwh, 0) > 0
          OR COALESCE(c.district_cooling_kwh, 0) > 0
        THEN TRUE ELSE FALSE
    END AS neighbor_uses_district,
    c.{fuel}_kwh AS baseline_fuel_kwh,
    b.{fuel}_kwh AS berdo_fuel_kwh,
    b.ghg_kgco2e AS berdo_total_ghg_kgco2e,
    b.{fuel_ghg} AS berdo_fuel_ghg_kgco2e
FROM main.int_berdo_comstock_matches AS m
JOIN main.int_comstock_models AS c
  ON c.comstock_id = m.comstock_id AND c.upgrade_id = 0
JOIN main.stg_berdo__buildings AS b
  ON b.berdo_id = m.berdo_id
WHERE m.berdo_id = ?
ORDER BY m.match_rank, m.distance, m.comstock_id
"""


def analyze_case(con, berdo_id, fuel):
    if fuel not in VALID_FUELS:
        raise ValueError(f'Unknown fuel: {fuel}')
    sql = SQL.format(fuel=fuel, fuel_ghg=f'{fuel}_ghg_kgco2e')
    df = con.execute(sql, [berdo_id]).df()
    if df.empty:
        print(f'WARNING: No baseline neighbors for BERDO {berdo_id}')
        return
    df['uses_fuel'] = df['baseline_fuel_kwh'].gt(0)
    df['weight_share_pct'] = 100 * df['match_weight'] / df['match_weight'].sum()
    df['weighted_fuel_baseline_kwh'] = df['match_weight'] * df['baseline_fuel_kwh']
    coverage = df.loc[df['uses_fuel'], 'weight_share_pct'].sum()
    fuel_users = df[df['uses_fuel']]
    fuel_ghg = df['berdo_fuel_ghg_kgco2e'].iloc[0]
    total_ghg = df['berdo_total_ghg_kgco2e'].iloc[0]
    emissions_share = 100 * fuel_ghg / total_ghg if pd.notna(total_ghg) and total_ghg > 0 else float('nan')

    print(f'\nBERDO {berdo_id} | {fuel}')
    print(f'  Neighbors: {len(df)} | Fuel-using neighbors: {len(fuel_users)}')
    print(f'  Weighted fuel coverage: {coverage:.2f}% | BERDO fuel emissions share: {emissions_share:.2f}%')
    print(f'  Missing neighbor fuel baseline: {df["baseline_fuel_kwh"].isna().sum()}')
    if not fuel_users.empty:
        print(f'  Fuel-using neighbor ranks: {fuel_users["match_rank"].tolist()}')
    print(df[['match_rank', 'comstock_id', 'distance', 'match_weight',
              'weight_share_pct', 'baseline_fuel_kwh', 'uses_fuel']]
          .round(3).to_string(index=False))

    stem = f'{berdo_id}_{fuel}'
    df.to_csv(OUT / f'{stem}_neighbors.csv', index=False)

    # Check that distance components reproduce the matching distance.
    components = ["size_gap", "eui_gap", "fuel_share_gap", "stories_gap"]

    calculated_distance = df[components].sum(axis=1)
    max_difference = (calculated_distance - df["distance"]).abs().max()

    if max_difference > 1e-5:
        print(
            f"WARNING: Distance components differ from total distance "
            f"by up to {max_difference:.6f}"
        )

    # Check district-energy compatibility.
    berdo_district = bool(df["berdo_uses_district"].iloc[0])
    district_agreement = (
        df["neighbor_uses_district"] == berdo_district
    ).sum()

    print(
        f"  BERDO uses district energy: {berdo_district} | "
        f"District-compatible neighbors: {district_agreement}/{len(df)}"
    )

    # Create one stacked distance chart per BERDO building.
    fig, ax = plt.subplots(figsize=(12, 5.5), layout="constrained")

    ranks = df["match_rank"].to_numpy()
    bottoms = pd.Series(0.0, index=df.index)

    component_labels = {
        "size_gap": "Floor area",
        "eui_gap": "EUI",
        "fuel_share_gap": "Fuel shares",
        "stories_gap": "Stories",
    }

    for component in components:
        ax.bar(
            ranks,
            df[component],
            bottom=bottoms,
            label=component_labels[component],
            width=0.75,
        )
        bottoms += df[component]

    # Mark neighbors that consume the investigated fuel.
    fuel_users = df["uses_fuel"]

    ax.scatter(
        df.loc[fuel_users, "match_rank"],
        df.loc[fuel_users, "distance"] + 0.05,
        marker="v",
        color="black",
        s=45,
        label=f"Uses {fuel.replace('_', ' ')}",
        zorder=5,
    )

    district_label = "Yes" if berdo_district else "No"

    ax.set_title(
        f"{df['building_address'].iloc[0] if 'building_address' in df else f'BERDO {berdo_id}'}"
        f" — {fuel.replace('_', ' ').title()}\n"
        f"Fuel coverage: {coverage:.1f}% | "
        f"District energy (BERDO): {district_label} | "
        f"Neighbors with matching district status: {district_agreement}/{len(df)}"
    )

    ax.set_xlabel("Neighbor rank")
    ax.set_ylabel("Matching distance (lower is closer)")
    ax.set_xticks(ranks)
    ax.grid(axis="y", alpha=0.2)
    ax.set_axisbelow(True)
    ax.legend(
        loc="upper center",
        bbox_to_anchor=(0.5, 1.16),
        ncol=5,
        frameon=False,
    )

    fig.savefig(OUT / f"{stem}_neighbors.png", dpi=170)
    plt.close(fig)


def main():
    if not DB.exists():
        raise SystemExit(f'Cannot find {DB}. Run this script from the dbt directory.')
    OUT.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB), read_only=True)
    try:
        for berdo_id, fuel in CASES:
            analyze_case(con, berdo_id, fuel)
    finally:
        con.close()
    print(f'\nCSV tables and PNG plots saved to {OUT}')


if __name__ == '__main__':
    main()
