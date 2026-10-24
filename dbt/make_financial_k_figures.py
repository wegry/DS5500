"""Create presentation/report figures for BERDO financial k sensitivity.

In the DS5500/dbt folder:
    python financial_k_sensitivity.py
    python make_financial_k_figures.py

Requires: python -m pip install matplotlib duckdb
Uses read-only dbt DuckDB queries and the CSVs from financial_k_sensitivity.py.
Figures saved to analysis_outputs/figures in PNG (slides) and SVG (report).

For reproducing the *observed* figures shown in the ChatGPT conversation,
run with --verified-preview. This mode uses the validated terminal numbers from
24 Oct 2026 instead of querying DuckDB; regenerate normally from the project
before updating the final report.
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter, MaxNLocator

K_VALUES = (1, 3, 5, 10)
K_TEST = (1, 3, 5)
VERSION = 'DS5500  |  BERDO + ComStock + BTB  |  2030–2034'
NOTE = 'k = matched ComStock neighbors. Fixed installation costs and applicability; five-year ACP; operating savings excluded.'


def use_font():
    plt.rcParams.update({
        'font.family': 'DejaVu Sans',
        'font.size': 11,
        'axes.titlesize': 19,
        'axes.titleweight': 'semibold',
        'axes.labelsize': 11,
        'savefig.dpi': 220,
        'figure.facecolor': 'white',
        'axes.facecolor': 'white',
        'axes.spines.top': False,
        'axes.spines.right': False,
        'axes.edgecolor': '0.78',
        'axes.labelcolor': '0.25',
        'xtick.color': '0.35',
        'ytick.color': '0.35',
    })


def base(title, subtitle):
    fig = plt.figure(figsize=(12, 6.75))
    ax = fig.add_axes((0.12, 0.25, 0.80, 0.47))
    fig.text(0.07, 0.91, title, fontsize=20, weight='bold', va='top')
    fig.text(0.07, 0.835, subtitle, fontsize=11.4, va='top', color='0.38')
    fig.text(0.07, 0.13, NOTE, fontsize=9.1, color='0.38')
    fig.text(0.07, 0.085, VERSION, fontsize=9.1, color='0.49')
    return fig, ax


def export(fig, outdir, stem):
    for ext in ('png', 'svg'):
        fig.savefig(outdir / f'{stem}.{ext}', facecolor='white', dpi=220)
    plt.close(fig)


def compliance_figure(outdir, above_limit, available):
    fig, ax = base('How many offices have a compliant retrofit?',
                   f'Of {above_limit} offices above the 2030 standard, {available} have a modeled compliant option among the 8 tested.')
    unavailable = above_limit - available
    ax.barh([0], [available], height=0.50, label='Compliant retrofit available')
    ax.barh([0], [unavailable], left=[available], height=0.50, label='No compliant retrofit among tested options')
    ax.set_xlim(0, max(above_limit * 1.08, 110))
    ax.set_ylim(-0.7, 0.7)
    ax.set_yticks([])
    ax.set_xlabel('Number of above-limit offices')
    ax.xaxis.set_major_locator(MaxNLocator(integer=True, nbins=6))
    ax.spines[['left', 'bottom']].set_visible(False)
    ax.text(available/2, 0, f'{available}\n{available/above_limit:.1%}', va='center', ha='center', color='white', fontsize=17, weight='bold')
    ax.text(available + unavailable/2, 0, f'{unavailable}\n{unavailable/above_limit:.1%}', va='center', ha='center', color='white', fontsize=16, weight='bold')
    ax.legend(loc='upper center', bbox_to_anchor=(0.5, -0.09), ncol=2, frameon=False, fontsize=10)
    export(fig, outdir, '01_compliance_availability')


def recommendation_figure(outdir, summary):
    fig, ax = base('When do compliant retrofit recommendations change?',
                  'Compared with k = 10, among the 64 offices with a compliant option (lower = more stable).')
    count = [int(summary[k]['different_recommendations']) for k in K_TEST]
    denominator = [int(summary[k]['compliant_buildings_compared']) for k in K_TEST]
    bars = ax.bar([f'k = {k}' for k in K_TEST], count, width=0.55)
    ax.set_ylabel('Offices with a different cheapest compliant option')
    ax.set_ylim(0, max(count) + 5)
    ax.yaxis.set_major_locator(MaxNLocator(integer=True, nbins=6))
    ax.yaxis.grid(True, alpha=0.18)
    ax.set_axisbelow(True)
    for bar,n,d in zip(bars,count,denominator):
        ax.annotate(f'{n} of {d}   ({n/d:.1%})',
                    (bar.get_x() + bar.get_width()/2, n),
                    xytext=(0,8), textcoords='offset points', ha='center', fontsize=12, weight='bold')
    fig.text(0.07, 0.19, 'One change in each comparison was effectively tied (<$1 difference).', color='0.35', fontsize=10)
    export(fig, outdir, '02_recommendation_sensitivity')


def cost_figure(outdir, summary, column, title, sub, filename):
    fig, ax = base(title, sub)
    vals = [float(summary[k][column]) for k in K_TEST]
    bars = ax.bar([f'k = {k}' for k in K_TEST], vals, width=0.55)
    ax.yaxis.set_major_formatter(FuncFormatter(lambda y,_: f'${y:,.0f}'))
    ax.set_ylim(0, max(vals) * 1.33)
    ax.yaxis.grid(True, alpha=0.18)
    ax.set_axisbelow(True)
    ax.set_ylabel('Additional modeled 5-year cost (USD)')
    for bar,val in zip(bars,vals):
        ax.annotate(f'${val:,.0f}', (bar.get_x() + bar.get_width()/2, val),
                    xytext=(0,8), textcoords='offset points', ha='center', fontsize=12, weight='bold')
    fig.text(0.07,0.18,
        'Penalty of keeping the k=10 choice when another compliant option is cheaper at this k.',
        color='0.35', fontsize=10)
    fig.text(0.07,0.155,
        'Only cases where the k=10 choice remains compliant; excludes noncompliant choices.',
        color='0.35', fontsize=10)
    export(fig, outdir, filename)


def cases_figure(outdir, case_data):
    fig = plt.figure(figsize=(12,6.75))
    fig.text(0.07, 0.91, 'Two buildings reveal the practical trade-off', fontsize=20, weight='bold', va='top')
    fig.text(0.07, 0.83,
        'Additional cost to choose a compliant retrofit instead of the lowest-cost retrofit.',
        fontsize=11.3, va='top', color='0.38')
    ax = fig.add_axes((0.06,0.24,0.88,0.48)); ax.axis('off')
    columns = ['Building','k','Cheapest overall retrofit','Cheapest compliant retrofit','Premium']
    table_rows = []
    for r in case_data:
        cheapest = r['cheapest'].replace('Wall Insulation','Wall insulation').replace('Roof Insulation','Roof insulation')
        compatible = r['compliant'].replace('Package 2, LED Lighting + Variable Speed HP RTU or HP Boilers','Package 2')
        compatible = compatible.replace('Package 4, Package 2 with Standard Performance HP RTU','Package 4')
        compatible = compatible.replace('Wall Insulation','Wall insulation').replace('Roof Insulation','Roof insulation').replace('LED Lighting','LED lighting')
        table_rows.append([str(r['berdo_id']), str(r['k']), cheapest, compatible,
                           f"${r['premium']:,.0f}"])
    tab = ax.table(cellText=table_rows, colLabels=columns, cellLoc='left', colLoc='left',
                   loc='center', colWidths=[0.14,0.07,0.25,0.38,0.16])
    tab.auto_set_font_size(False); tab.set_fontsize(10.3); tab.scale(1, 1.65)
    for (i,j), cell in tab.get_celld().items():
        cell.set_linewidth(0.35);cell.set_edgecolor('0.85')
        if i == 0:
            cell.set_facecolor('0.88');cell.set_text_props(weight='bold')
        elif i % 2 == 0:cell.set_facecolor('0.96')
    fig.text(0.07,0.18,
             'Package 2: LED + variable-speed heat-pump RTU / HP boiler. Package 4: standard-performance HP RTU.',
             fontsize=9.5,color='0.35')
    fig.text(0.07,0.145,
             'Premium compares retrofit options, not the ACP-only/no-upgrade choice.',
             fontsize=9.5,color='0.35')
    fig.text(0.07,0.10,NOTE,fontsize=9.1,color='0.38')
    fig.text(0.07,0.06,VERSION,fontsize=9.1,color='0.49')
    export(fig, outdir,'05_case_study_compliance_premiums')


def verified_preview_data():
    # Exact values reported by the user from their Oct 24 analysis terminal output.
    summary = {
      1: {'different_recommendations':12,'compliant_buildings_compared':64,
          'median_extra_cost_usd_excluding_noncompliant':5060.80,
          'max_extra_cost_usd_excluding_noncompliant':29380.55},
      3: {'different_recommendations':9,'compliant_buildings_compared':64,
          'median_extra_cost_usd_excluding_noncompliant':2804.60,
          'max_extra_cost_usd_excluding_noncompliant':14341.46},
      5: {'different_recommendations':9,'compliant_buildings_compared':64,
          'median_extra_cost_usd_excluding_noncompliant':1294.28,
          'max_extra_cost_usd_excluding_noncompliant':121316.44},
    }
    examples = [
      (101505,1,'Wall Insulation','Package 2, LED Lighting + Variable Speed HP RTU or HP Boilers',427009.13),
      (101505,3,'Wall Insulation','Package 2, LED Lighting + Variable Speed HP RTU or HP Boilers',416589.56),
      (101505,5,'Wall Insulation','Package 2, LED Lighting + Variable Speed HP RTU or HP Boilers',429553.97),
      (101505,10,'Wall Insulation','Package 4, Package 2 with Standard Performance HP RTU',412782.65),
      (103036,1,'Roof Insulation','Wall Insulation',33623.48),
      (103036,3,'Roof Insulation','LED Lighting',19988.97),
      (103036,5,'Roof Insulation','Roof Insulation',0),
      (103036,10,'Roof Insulation','Roof Insulation',0),
    ]
    return 99,64,summary,[dict(berdo_id=b,k=k,cheapest=ch,compliant=co,premium=p) for b,k,ch,co,p in examples]


def from_project(db_folder):
    import duckdb
    # Existing reproducible financial analysis writes summary/choice CSVs.
    out = db_folder / 'analysis_outputs'
    required = [out / 'financial_k_summary.csv', out / 'financial_k_choices.csv']
    absent = [str(p) for p in required if not p.exists()]
    if absent:
        raise SystemExit('Missing sensitivity CSVs: ' + ', '.join(absent) +
                         '\nFirst run: python financial_k_sensitivity.py')
    with required[0].open(newline='',encoding='utf-8') as f:
        summary = {int(r['k']):r for r in csv.DictReader(f)}
    with required[1].open(newline='',encoding='utf-8') as f:
        choice_rows = list(csv.DictReader(f))
    available = len({int(r['berdo_id']) for r in choice_rows if int(r['k'])==10})
    dbs = list(db_folder.glob('*.duckdb'))
    if len(dbs) != 1:
        raise SystemExit(f'Expected one DuckDB database in {db_folder}, found {len(dbs)}')
    with duckdb.connect(str(dbs[0]),read_only=True) as con:
        above_limit = con.execute('''
            SELECT COUNT(*) FROM berdo_decisions
            WHERE is_compliance_period
              AND baseline_ghg_intensity_kgco2e_sqft > standard_kgco2e_sqft
        ''').fetchone()[0]
        rate = con.execute('''
            SELECT MEDIAN(acp_usd_per_year / excess_kgco2e)
            FROM berdo_decision_options WHERE is_compliance_period AND excess_kgco2e>0
        ''').fetchone()[0]
        rows = con.execute('''
            SELECT s.k, s.berdo_id, s.upgrade_id, o.upgrade_name,
                   s.meets_standard_after,
                   o.installed_cost_mid_usd + GREATEST(0,
                   s.projected_ghg_kgco2e - o.standard_kgco2e_sqft * d.gfa_sqft)
                   * ? * o.period_years AS total_usd
            FROM berdo_matching_k_sensitivity s
            JOIN berdo_decision_options o USING (berdo_id, upgrade_id)
            JOIN berdo_decisions d USING (berdo_id)
            WHERE o.is_compliance_period AND d.is_compliance_period
              AND d.baseline_ghg_intensity_kgco2e_sqft>d.standard_kgco2e_sqft
              AND s.upgrade_id<>0 AND o.applicable_share>0
              AND o.installed_cost_mid_usd IS NOT NULL
              AND s.berdo_id IN (101505,103036)
        ''',[rate]).fetchall()
    cases = []
    for bid in (101505,103036):
        for k in K_VALUES:
            options = sorted([r for r in rows if r[0]==k and r[1]==bid],key=lambda r:(r[5],r[2]))
            eligible = [r for r in options if r[4]]
            if not options or not eligible:
                continue
            a, b = options[0],eligible[0]
            cases.append({'berdo_id':bid,'k':k,'cheapest':a[3],
                          'compliant':b[3],'premium':max(0.0,b[5]-a[5])})
    return above_limit,available,summary,cases


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--verified-preview',action='store_true',help='Use confirmed Oct 24 terminal results')
    p.add_argument('--output-dir',type=Path,default=None)
    args = p.parse_args()
    here = Path(__file__).resolve().parent
    if args.verified_preview:
        above,available,summary,cases = verified_preview_data()
        outdir = args.output_dir or (here / 'financial_visuals_preview')
    else:
        above,available,summary,cases = from_project(here)
        outdir = args.output_dir or (here / 'analysis_outputs' / 'figures')
    outdir.mkdir(parents=True,exist_ok=True)
    use_font()
    compliance_figure(outdir,above,available)
    recommendation_figure(outdir,summary)
    cost_figure(outdir,summary,'median_extra_cost_usd_excluding_noncompliant',
                'Typical cost of a changed recommendation',
                'Median penalty among changed cases where the k=10 choice remains compliant.',
                '03_median_extra_cost')
    cost_figure(outdir,summary,'max_extra_cost_usd_excluding_noncompliant',
                'Largest cost exposure from using the k=10 choice',
                'Maximum penalty among changed cases where the k=10 choice remains compliant.',
                '04_maximum_extra_cost')
    if cases:
        cases_figure(outdir,cases)
    print(f'Figures saved: {outdir}')
    for f in sorted(outdir.glob('*.png')):print('  ',f.name)
    print('PNG for slides; SVG for Word/report. Figures exclude energy operating savings.')


if __name__ == '__main__': main()
