"""
ICT-MT5 Equity Curve Visualizer
"""
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import numpy as np

eq = pd.read_csv('/home/workspace/Projects/ict-automation/docs/equity_curve.csv', parse_dates=['date'])
eq.set_index('date', inplace=True)

START = 500
eq['pct_return'] = (eq['equity'] - START) / START * 100

fig, axes = plt.subplots(2, 1, figsize=(14, 8), gridspec_kw={'height_ratios': [3, 1]})
fig.patch.set_facecolor('#0d1117')
for ax in axes:
    ax.set_facecolor('#161b22')

# Equity curve
ax = axes[0]
ax.plot(eq.index, eq['equity'], color='#58a6ff', linewidth=1.5, label='Equity (R)')
ax.fill_between(eq.index, START, eq['equity'],
               where=(eq['equity'] >= START), color='#238636', alpha=0.3)
ax.fill_between(eq.index, START, eq['equity'],
               where=(eq['equity'] < START), color='#da3633', alpha=0.3)
ax.axhline(START, color='#8b949e', linestyle='--', linewidth=1, alpha=0.7)
ax.set_ylabel('Equity (ZAR)', color='#c9d1d9', fontsize=11)
ax.set_title('ICT-MT5 EA Backtest — XAUUSD | R500 | 1% Risk | 1:3 Target\n86 Trades | 25.6% Win Rate | Max DD 1.4%',
             color='#f0f6fc', fontsize=13, fontweight='bold')
ax.tick_params(colors='#8b949e')
ax.yaxis.label.set_color('#8b949e')
ax.spines['bottom'].set_color('#30363d')
ax.spines['left'].set_color('#30363d')
ax.spines['top'].set_color('#30363d')
ax.spines['right'].set_color('#30363d')
ax.grid(True, color='#21262d', linewidth=0.5)
ax.legend(facecolor='#161b22', edgecolor='#30363d', labelcolor='#c9d1d9')

# Drawdown %
ax2 = axes[1]
peak = eq['equity'].cummax()
dd = (eq['equity'] - peak) / peak * 100
ax2.fill_between(eq.index, 0, dd, color='#da3633', alpha=0.6)
ax2.set_ylabel('Drawdown %', color='#c9d1d9', fontsize=10)
ax2.set_xlabel('Date', color='#8b949e')
ax2.tick_params(colors='#8b949e')
ax2.spines['bottom'].set_color('#30363d')
ax2.spines['left'].set_color('#30363d')
ax2.spines['top'].set_color('#30363d')
ax2.spines['right'].set_color('#30363d')
ax2.grid(True, color='#21262d', linewidth=0.5)

plt.tight_layout()
out_path = '/home/workspace/Projects/ict-automation/docs/backtest_equity_curve.png'
plt.savefig(out_path, dpi=150, bbox_inches='tight', facecolor=fig.get_facecolor())
plt.close()
print(f"Chart saved → {out_path}")

# Summary stats
print(f"\nFinal equity  : R{eq['equity'].iloc[-1]:.2f}")
print(f"Max equity    : R{eq['equity'].max():.2f}")
print(f"Min equity    : R{eq['equity'].min():.2f}")
print(f"Max DD        : {dd.min():.2f}%")
print(f"Total days    : {len(eq)}")