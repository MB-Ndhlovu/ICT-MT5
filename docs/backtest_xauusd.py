"""
ICT-MT5 Backtester — XAUUSD (Gold Futures)
Simulates R500 starting capital, 1% risk per trade, 1:3 target.
Uses ICT signal logic on real historical Gold data (GC=F futures).
"""

import yfinance as yf
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import warnings
warnings.filterwarnings('ignore')

# ─── CONFIG ────────────────────────────────────────────
START_CAPITAL_ZAR  = 500        # R500
RISK_PCT            = 0.01     # 1% per trade
TARGET_R            = 3        # 1:3 risk:reward
DAILY_LOSS_CAP_PCT  = 0.02     # -2% daily cap
ZAR_PER_USD         = 18.5     # approximate ZAR/USD rate
INITIAL_CAPITAL_ZAR = START_CAPITAL_ZAR
SYMBOL              = "GC=F"   # Gold Comex Futures

# Approximate XAUUSD pip values (MT5 lot sizing)
# XAUUSD: 1 standard lot = 100 oz | Point = 0.01
# For simulation we use $ per point × ZAR conversion
TRAILING_STOP_TICK_P = 15       # trailing activation after 1R move

# ─── DATA ──────────────────────────────────────────────
print("Downloading Gold futures historical data...")
# Get 2 years of daily data + 6mo of H1 intraday for signal generation
data = yf.download(SYMBOL, period="2y", interval="1d", auto_adjust=True, progress=False)
# Handle MultiIndex columns from yfinance
if isinstance(data.columns, pd.MultiIndex):
    data.columns = [col[0] for col in data.columns]
data.columns = data.columns.str.lower()
data = data.dropna()

# Use H1 intraday for more signals
data_h1 = yf.download(SYMBOL, period="6mo", interval="1h", auto_adjust=True, progress=False)
if isinstance(data_h1.columns, pd.MultiIndex):
    data_h1.columns = [col[0] for col in data_h1.columns]
data_h1.columns = data_h1.columns.str.lower()
data_h1 = data_h1.dropna()

print(f"Daily bars : {len(data)}")
print(f"H1 bars    : {len(data_h1)}")
print(f"Date range : {data.index[0].date()} → {data.index[-1].date()}")

# ─── ICT SIGNAL LOGIC ───────────────────────────────────
def compute_indicators(df):
    """Compute ICT-aligned indicators on OHLC data."""
    o, h, l, c = df['open'], df['high'], df['low'], df['close']

    # Swing highs / lows (simple pivot approach)
    roll = 5
    highs = h.rolling(roll+1).max().shift(-1)
    lows  = l.rolling(roll+1).min().shift(-1)

    is_swing_high  = (h > highs) & (h.shift(1) > h.shift(-1))
    is_swing_low   = (l < lows)  & (l.shift(1) < l.shift(-1))

    # EMA 21 for trend direction
    ema21 = c.ewm(span=21).mean()

    # ATR for stop placement
    tr = np.maximum(h - l, np.maximum(abs(h - c.shift(1)), abs(l - c.shift(1))))
    atr = tr.rolling(14).mean()

    # Detect fair value gaps (3-bar imbalance)
    fvg_up = (c.shift(2) < o.shift(1)) & (o > c.shift(1))   # bullish FVG
    fvg_dn = (c.shift(2) > o.shift(1)) & (o < c.shift(1))   # bearish FVG

    # Kill zone hours (London: 8-11 SAST? = 3-6 UTC; NY: 14-17 UTC)
    # Simplified: use hour of timestamp
    hour = df.index.hour
    is_kill_zone_london = ((hour >= 8) & (hour <= 11))
    is_kill_zone_ny     = ((hour >= 14) & (hour <= 17))

    # 50% Fib zone (yesterday range)
    daily_data = data.copy()  # use daily for macro context
    # We compute yesterday's high/low
    prev_high = h.shift(1).rolling(5).max()
    prev_low  = l.shift(1).rolling(5).min()
    mid_zone  = (prev_high + prev_low) / 2

    out = pd.DataFrame(index=df.index)
    out['close']       = c
    out['high']        = h
    out['low']         = l
    out['ema21']       = ema21
    out['atr']         = atr
    out['swing_high']  = is_swing_high
    out['swing_low']   = is_swing_low
    out['bull_fvg']    = fvg_up
    out['bear_fvg']    = fvg_dn
    out['kill_london'] = is_kill_zone_london
    out['kill_ny']     = is_kill_zone_ny
    out['prev_high']   = prev_high
    out['prev_low']    = prev_low
    out['mid_zone']    = mid_zone

    return out

print("Computing ICT indicators...")
df = compute_indicators(data_h1)

# ─── SIMULATION ENGINE ─────────────────────────────────
def run_backtest(df, starting_capital):
    equity     = starting_capital
    trades     = []
    wins       = 0
    losses     = 0
    streaks    = []
    daily_pnl  = []
    daily_loss_streak = 0
    in_trade   = False
    trade_open = None
    bars_in_trade = 0

    # Track what "session day" we're in for daily cap
    current_date = None
    day_loss = 0.0

    entries = []
    exits   = []
    equity_curve = []

    print(f"\nStarting backtest — R{starting_capital} initial, 1% risk, 1:{TARGET_R} target")
    print("=" * 60)

    for i in range(50, len(df) - 5):
        row      = df.iloc[i]
        next_bar = df.iloc[i+1] if i+1 < len(df) else None

        date = row.name
        is_new_day = current_date != date.date()
        if is_new_day:
            current_date = date.date()
            day_loss = 0.0

        # Skip if daily loss cap hit
        if abs(day_loss) >= (DAILY_LOSS_CAP_PCT * equity):
            if in_trade:  # close at market
                close_px = row['close']
                pnl = (close_px - trade_open['entry']) / trade_open['entry'] * trade_open['size']
                equity += pnl
                trades.append({**trade_open, 'exit': close_px, 'pnl_zAR': pnl, 'type': 'daily_cap_close'})
                in_trade = False
            equity_curve.append((date, equity))
            continue

        if in_trade:
            bars_in_trade += 1
            # Check stop loss / take profit
            sl = trade_open['stop_loss']
            tp = trade_open['take_profit']
            direction = trade_open['direction']

            if direction == 'long':
                if row['low']  <= sl:  # stop hit
                    pnl = (sl - trade_open['entry']) / trade_open['entry'] * trade_open['size']
                    equity += pnl
                    trades.append({**trade_open, 'exit': sl, 'pnl_zAR': pnl, 'reason': 'sl', 'bars': bars_in_trade})
                    in_trade = False
                    day_loss += pnl
                elif row['high'] >= tp:  # tp hit
                    pnl = (tp - trade_open['entry']) / trade_open['entry'] * trade_open['size']
                    equity += pnl
                    trades.append({**trade_open, 'exit': tp, 'pnl_zAR': pnl, 'reason': 'tp', 'bars': bars_in_trade})
                    in_trade = False
                    day_loss += pnl
                    wins += 1
            else:  # short
                if row['high'] >= sl:
                    pnl = (trade_open['entry'] - sl) / trade_open['entry'] * trade_open['size']
                    equity += pnl
                    trades.append({**trade_open, 'exit': sl, 'pnl_zAR': pnl, 'reason': 'sl', 'bars': bars_in_trade})
                    in_trade = False
                    day_loss += pnl
                elif row['low'] <= tp:
                    pnl = (trade_open['entry'] - tp) / trade_open['entry'] * trade_open['size']
                    equity += pnl
                    trades.append({**trade_open, 'exit': tp, 'pnl_zAR': pnl, 'reason': 'tp', 'bars': bars_in_trade})
                    in_trade = False
                    day_loss += pnl
                    wins += 1

            equity_curve.append((date, equity))
            continue

        # ── ENTRY LOGIC (ICT) ─────────────────────────────
        if i < 5 or pd.isna(row['atr']) or row['atr'] == 0:
            continue

        # Trend: EMA 21
        trend_up   = row['close'] > row['ema21']
        trend_down = row['close'] < row['ema21']

        # Kill zone filter (only trade in kill zones for more institutional flow)
        in_kill = row['kill_london'] or row['kill_ny']

        # FVG present + trend alignment = entry
        bull_setup = row['bull_fvg'] and trend_up
        bear_setup = row['bear_fvg'] and trend_down

        entry_price = row['close']

        if bull_setup:
            risk_zAR  = equity * RISK_PCT
            sl_dist   = row['atr'] * 1.5          # 1.5 ATR stop
            tp_dist   = sl_dist * TARGET_R         # 1:3 → 3× ATR target
            stop_loss = entry_price - sl_dist
            take_profit = entry_price + tp_dist

            # size: how many XAUUSD units for 1% risk
            risk_per_unit = (sl_dist / entry_price) * ZAR_PER_USD
            size = risk_zAR / risk_per_unit if risk_per_unit > 0 else 0

            trade_open = {
                'entry': entry_price, 'stop_loss': stop_loss,
                'take_profit': take_profit, 'direction': 'long',
                'size': size, 'risk_zAR': risk_zAR,
                'entry_time': date, 'pnl_zAR': 0,
                'rr_used': TARGET_R
            }
            in_trade = True
            bars_in_trade = 0

        elif bear_setup:
            risk_zAR  = equity * RISK_PCT
            sl_dist   = row['atr'] * 1.5
            tp_dist   = sl_dist * TARGET_R
            stop_loss = entry_price + sl_dist
            take_profit = entry_price - tp_dist

            risk_per_unit = (sl_dist / entry_price) * ZAR_PER_USD
            size = risk_zAR / risk_per_unit if risk_per_unit > 0 else 0

            trade_open = {
                'entry': entry_price, 'stop_loss': stop_loss,
                'take_profit': take_profit, 'direction': 'short',
                'size': size, 'risk_zAR': risk_zAR,
                'entry_time': date, 'pnl_zAR': 0,
                'rr_used': TARGET_R
            }
            in_trade = True
            bars_in_trade = 0

    return trades, equity_curve, equity

trades, equity_curve, final_equity = run_backtest(df, START_CAPITAL_ZAR)

# ─── RESULTS ───────────────────────────────────────────
print("\n" + "=" * 60)
print("BACKTEST RESULTS — XAUUSD (ICT Strategy)")
print("=" * 60)

if not trades:
    print("⚠ No trades generated. Check data coverage and signal logic.")
else:
    wins   = [t for t in trades if t.get('reason') == 'tp']
    losses = [t for t in trades if t.get('reason') == 'sl']
    win_rate = len(wins) / len(trades) * 100

    total_pnl   = sum(t['pnl_zAR'] for t in trades)
    total_wins  = sum(t['pnl_zAR'] for t in wins)
    total_loss  = sum(t['pnl_zAR'] for t in losses)
    avg_win     = total_wins / len(wins) if wins else 0
    avg_loss    = abs(total_loss / len(losses)) if losses else 0

    # Simulated Sharpe (equity curve based)
    returns = [eq[1] for eq in equity_curve]
    if len(returns) > 1:
        rets = np.diff(returns) / returns[:-1]
        sharpe = (np.mean(rets) / np.std(rets)) * np.sqrt(252) if np.std(rets) > 0 else 0
    else:
        sharpe = 0

    # Max drawdown
    peak = START_CAPITAL_ZAR
    max_dd = 0
    for _, eq in equity_curve:
        if eq > peak:
            peak = eq
        dd = (peak - eq) / peak * 100
        if dd > max_dd:
            max_dd = dd

    print(f"\n📊 ACCOUNT: R{START_CAPITAL_ZAR} → R{final_equity:.2f}")
    print(f"   Net P&L   : {'+' if total_pnl >= 0 else ''}R{total_pnl:.2f}")
    print(f"   Return    : {((final_equity - START_CAPITAL_ZAR) / START_CAPITAL_ZAR * 100):.1f}%")
    print(f"\n📈 TRADES: {len(trades)} total | {len(wins)}W / {len(losses)}L")
    print(f"   Win Rate  : {win_rate:.1f}%")
    print(f"   Avg Win   : R{avg_win:.2f}")
    print(f"   Avg Loss  : R{avg_loss:.2f}")
    print(f"   Avg R     : {(avg_win/avg_loss) if avg_loss > 0 else 0:.2f}R")
    print(f"\n📉 RISK:")
    print(f"   Max DD    : {max_dd:.1f}%")
    print(f"   Sharpe    : {sharpe:.2f}")
    print(f"   Risk/trade: 1% | Target: 1:{TARGET_R}")

    print(f"\n📅 PERIOD: {df.index[50].date()} → {df.index[-6].date()}")
    print(f"   Duration  : ~{len(trades)} signals in 6 months")

    print("\n── SAMPLE TRADES (last 10) ──")
    for t in trades[-10:]:
        emoji = "✅" if t['reason'] == 'tp' else "❌"
        pnl_str = f"+R{t['pnl_zAR']:.2f}" if t['pnl_zAR'] >= 0 else f"-R{abs(t['pnl_zAR']):.2f}"
        print(f"  {emoji} {t['direction'].upper():5s} | {t['entry_time'].strftime('%Y-%m-%d %H:%M')} | Entry: {t['entry']:.2f} | Exit: {t['exit']:.2f} | {pnl_str}")

# Save equity curve
eq_df = pd.DataFrame(equity_curve, columns=['date', 'equity'])
eq_path = '/home/workspace/Projects/ict-automation/docs/equity_curve.csv'
eq_df.to_csv(eq_path, index=False)
print(f"\n💾 Equity curve saved → {eq_path}")
print(f"   Points: {len(eq_df)}")