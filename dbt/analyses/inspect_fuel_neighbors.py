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
    m.comstock_id,
    m.match_rank,
    m.distance,
    m.match_weight,
    m.size_gap,
    m.eui_gap,
    m.fuel_share_gap,
    m.stories_gap,
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

    fig, axes = plt.subplots(2, 1, figsize=(10, 7), sharex=True, layout='constrained')
    colors = df['uses_fuel'].map({True: 'tab:blue', False: 'tab:orange'})
    axes[0].bar(df['match_rank'], df['weight_share_pct'], color=colors)
    axes[0].set_ylabel('Share of total match weight (%)')
    axes[0].set_title(f'BERDO {berdo_id} — {fuel.replace("_", " ")} | coverage {coverage:.1f}%')
    axes[1].scatter(df.loc[df['uses_fuel'], 'match_rank'], df.loc[df['uses_fuel'], 'distance'],
                    label='Uses fuel', color='tab:blue', s=65)
    axes[1].scatter(df.loc[~df['uses_fuel'], 'match_rank'], df.loc[~df['uses_fuel'], 'distance'],
                    label='Does not use fuel', color='tab:orange', s=65)
    axes[1].set_ylabel('Matching distance (lower is closer)')
    axes[1].set_xlabel('Neighbor rank')
    axes[1].legend()
    axes[1].grid(alpha=0.2)
    axes[1].set_xticks(sorted(df['match_rank'].dropna().unique()))
    fig.savefig(OUT / f'{stem}_neighbors.png', dpi=170)
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
