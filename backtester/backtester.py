#!/usr/bin/env python3
"""
ICT-MT5 Backtester — R500 Account Simulation
Simulates ICT Smart Money Concepts across XAUUSD, NAS100, US30
with $500 starting capital and 1% risk per trade.

Author: Malibongwe Ndhlovu
Supervisor: Ben JARVIS AI
"""

import numpy as np
import pandas as pd
from dataclasses import dataclass, field
from typing import List, Optional
from datetime import datetime, timedelta
import json

np.random.seed(42)

# ─────────────────────────────────────────────────────────────
# MARKET DEFINITIONS
# ─────────────────────────────────────────────────────────────
MARKETS = {
    "XAUUSD": {
        "name": "Gold vs US Dollar",
        "point_value": 0.01,          # 1 pip = $0.01 for gold (cents)
        "pip_size": 0.5,              # ICT uses 0.5 as standard gold pip
        "spread_cost_per_pip": 1.5,   # spread in pips
        "daily_range_pips": 1500,
        "daily_trend_factor": 0.55,
        "volatility": 1.4,
    },
    "NAS100": {
        "name": "Nasdaq 100",
        "point_value": 0.25,          # $0.25 per point
        "pip_size": 0.25,
        "spread_cost_per_pip": 1.0,
        "daily_range_pips": 200,
        "daily_trend_factor": 0.52,
        "volatility": 1.1,
    },
    "US30": {
        "name": "Dow Jones 30",
        "point_value": 0.50,          # $0.50 per point
        "pip_size": 0.50,
        "spread_cost_per_pip": 2.0,
        "daily_range_pips": 250,
        "daily_trend_factor": 0.50,
        "volatility": 0.9,
    },
}

# ─────────────────────────────────────────────────────────────
# ACCOUNT PARAMETERS
# ─────────────────────────────────────────────────────────────
STARTING_CAPITAL_ZAR = 500
RISK_PER_TRADE_PCT = 0.01
DAILY_LOSS_CAP_PCT = 0.02

# ICT Parameters
STOPLoss_PIPS = {
    "XAUUSD": 8.0,    # 8 pip (40 cent) stop for gold
    "NAS100": 15.0,   # 15 pip stop for nasdaq
    "US30": 20.0,     # 20 pip stop for dow
}
TAKE_PROFIT_MULTIPLIER = 3.0   # 1:3 R:R

# ─────────────────────────────────────────────────────────────
# SYNTHETIC DATA GENERATOR
# ─────────────────────────────────────────────────────────────
def generate_ohlcv(symbol: str, days: int = 60, tf: str = "H1") -> pd.DataFrame:
    """Generate realistic synthetic OHLCV for a symbol."""
    cfg = MARKETS[symbol]
    n = days * 24 if tf == "H1" else days * 4

    # Base price
    base_prices = {"XAUUSD": 2350, "NAS100": 18500, "US30": 39000}
    base = base_prices[symbol]

    trend = cfg["daily_trend_factor"]
    vol = cfg["volatility"]

    trend_factor = (trend - 0.5) * 2  # convert 0.5→0, 0.55→0.1

    closes = [base]
    for i in range(1, n):
        daily_vol = cfg["daily_range_pips"] * vol / np.sqrt(n / days)
        ret = np.random.normal(trend_factor * 0.0002, daily_vol * 0.00015)
        closes.append(closes[-1] * (1 + ret))

    closes = np.array(closes)

    high = closes * (1 + np.abs(np.random.normal(0, 0.0008 * vol, n)))
    low  = closes * (1 - np.abs(np.random.normal(0, 0.0008 * vol, n)))
    open_prices = np.roll(closes, 1)
    open_prices[0] = closes[0]

    # Ensure OHLC relationships
    high = np.maximum(high, np.maximum(open_prices, closes))
    low  = np.minimum(low, np.minimum(open_prices, closes))

    dates = pd.date_range(start=datetime(2026, 3, 1), periods=n, freq="H")

    df = pd.DataFrame({
        "time": dates,
        "open": open_prices,
        "high": high,
        "low": low,
        "close": closes,
        "tick_volume": np.random.randint(100, 2000, n),
    })
    return df

# ─────────────────────────────────────────────────────────────
# ICT DETECTION FUNCTIONS
# ─────────────────────────────────────────────────────────────
def detect_swing_highs_lows(df: pd.DataFrame, lookback: int = 5) -> pd.DataFrame:
    """Find pivot highs and lows."""
    df = df.copy()
    df["swing_high"] = np.nan
    df["swing_low"]  = np.nan

    for i in range(lookback, len(df) - lookback):
        window_high = df["high"].iloc[i - lookback:i + lookback + 1]
        window_low  = df["low"].iloc[i - lookback:i + lookback + 1]

        if df["high"].iloc[i] == window_high.max():
            df.loc[df.index[i], "swing_high"] = df["high"].iloc[i]
        if df["low"].iloc[i] == window_low.min():
            df.loc[df.index[i], "swing_low"] = df["low"].iloc[i]

    return df

def detect_order_blocks(df: pd.DataFrame) -> List[dict]:
    """Detect bullish and bearish order blocks."""
    blocks = []
    df = detect_swing_highs_lows(df)

    for i in range(10, len(df) - 2):
        # Bullish OB: prior strong bearish candle followed by bullish confirmation
        body = df["close"].iloc[i] - df["open"].iloc[i]
        prev_body = df["open"].iloc[i - 1] - df["close"].iloc[i - 1]

        if prev_body < -0.5 * (df["high"].iloc[i-1] - df["low"].iloc[i-1]) and body > 0:
            blocks.append({
                "type": "bullish",
                "index": i,
                "time": df["time"].iloc[i],
                "top": max(df["close"].iloc[i], df["open"].iloc[i]),
                "bottom": min(df["close"].iloc[i], df["open"].iloc[i]),
            })

        # Bearish OB
        if prev_body > 0.5 * (df["high"].iloc[i-1] - df["low"].iloc[i-1]) and body < 0:
            blocks.append({
                "type": "bearish",
                "index": i,
                "time": df["time"].iloc[i],
                "top": max(df["close"].iloc[i], df["open"].iloc[i]),
                "bottom": min(df["close"].iloc[i], df["open"].iloc[i]),
            })

    return blocks

def detect_fvg(df: pd.DataFrame) -> List[dict]:
    """Detect Fair Value Gaps (3-candle imbalance)."""
    fvgs = []
    for i in range(2, len(df)):
        # Bullish FVG: candle 2 high < candle 1 low (gap up after bearish)
        # Bearish FVG: candle 2 low > candle 1 high (gap down after bullish)

        gap_up = df["high"].iloc[i - 1] < df["low"].iloc[i - 2]  # gap above
        gap_down = df["low"].iloc[i - 1] > df["high"].iloc[i - 2]  # gap below

        if gap_up and (df["close"].iloc[i] > df["open"].iloc[i]):
            fvgs.append({
                "type": "bullish",
                "index": i,
                "time": df["time"].iloc[i],
                "top": df["low"].iloc[i - 2],
                "bottom": df["high"].iloc[i - 1],
                "filled": False,
            })
        elif gap_down and (df["close"].iloc[i] < df["open"].iloc[i]):
            fvgs.append({
                "type": "bearish",
                "index": i,
                "time": df["time"].iloc[i],
                "top": df["high"].iloc[i - 1],
                "bottom": df["low"].iloc[i - 2],
                "filled": False,
            })

    return fvgs

def detect_liquidity_pools(df: pd.DataFrame, lookback: int = 20) -> dict:
    """Find recent highs/lows as liquidity pools."""
    recent_high = df["high"].iloc[-lookback:].max()
    recent_low  = df["low"].iloc[-lookback:].min()
    return {
        "buy_sl": recent_high,
        "sell_sl": recent_low,
        "range_high": recent_high,
        "range_low": recent_low,
    }

# ─────────────────────────────────────────────────────────────
# SIGNAL GENERATOR
# ─────────────────────────────────────────────────────────────
@dataclass
class Trade:
    symbol: str
    direction: str         # "buy" or "sell"
    entry_time: str
    entry_price: float
    stop_loss: float
    take_profit: float
    risk_amount_zar: float
    pnl_zar: float = 0.0
    result: str = ""       # "win", "loss", "breakeven"
    exit_time: str = ""
    exit_price: float = 0.0
    confidence: float = 0.0
    fvg_hits: int = 0
    ob_hits: int = 0

def generate_signals(df: pd.DataFrame, symbol: str, blocks: list, fvgs: list, liq: dict) -> List[Trade]:
    """Generate trade signals combining ICT concepts."""
    trades = []
    sl_pips = STOPLoss_PIPS[symbol]
    tp_pips = sl_pips * TAKE_PROFIT_MULTIPLIER
    cfg = MARKETS[symbol]

    for i in range(20, len(df) - 5):
        confidence = 0.0
        entry_price = df["close"].iloc[i]
        time_str = df["time"].iloc[i].strftime("%Y-%m-%d %H:%M")

        # ── Bullish Setup ──
        # Price near buy-side liquidity (recent low)
        near_buy_liq = liq["sell_sl"] * 1.001 <= entry_price <= liq["sell_sl"] * 1.005
        # Price above some swing lows (structure up)
        above_lows = df["close"].iloc[i] > df["low"].iloc[i - 5:i].min()
        # Bullish FVG below (untested gap)
        bullish_fvg_below = any(
            f["type"] == "bullish" and f["bottom"] < entry_price and not f.get("filled", False)
            for f in fvgs if abs(f["index"] - i) <= 10
        )
        # Bullish OB below entry
        bullish_ob_below = any(
            b["type"] == "bullish" and b["bottom"] < entry_price
            for b in blocks if abs(b["index"] - i) <= 15
        )

        score = int(near_buy_liq) + int(above_lows) + int(bullish_fvg_below) + int(bullish_ob_below)
        if score >= 3:
            sl = entry_price - (sl_pips * cfg["pip_size"])
            tp = entry_price + (tp_pips * cfg["pip_size"])
            risk_zar = STARTING_CAPITAL_ZAR * RISK_PER_TRADE_PCT

            # Check if stop is near liquidity sweep
            ob_count = sum(1 for b in blocks if b["type"] == "bullish" and abs(b["index"] - i) <= 15)
            fvg_count = sum(1 for f in fvgs if f["type"] == "bullish" and abs(f["index"] - i) <= 10)

            trade = Trade(
                symbol=symbol,
                direction="buy",
                entry_time=time_str,
                entry_price=entry_price,
                stop_loss=sl,
                take_profit=tp,
                risk_amount_zar=risk_zar,
                confidence=min(score / 4.0, 1.0),
                fvg_hits=fvg_count,
                ob_hits=ob_count,
            )
            trades.append(trade)
            continue

        # ── Bearish Setup ──
        near_sell_liq = liq["buy_sl"] * 0.999 >= entry_price >= liq["buy_sl"] * 0.995
        below_highs = df["close"].iloc[i] < df["high"].iloc[i - 5:i].max()
        bearish_fvg_below = any(
            f["type"] == "bearish" and f["top"] > entry_price and not f.get("filled", False)
            for f in fvgs if abs(f["index"] - i) <= 10
        )
        bearish_ob_below = any(
            b["type"] == "bearish" and b["top"] > entry_price
            for b in blocks if abs(b["index"] - i) <= 15
        )

        score = int(near_sell_liq) + int(below_highs) + int(bearish_fvg_below) + int(bearish_ob_below)
        if score >= 3:
            sl = entry_price + (sl_pips * cfg["pip_size"])
            tp = entry_price - (tp_pips * cfg["pip_size"])
            risk_zar = STARTING_CAPITAL_ZAR * RISK_PER_TRADE_PCT

            ob_count = sum(1 for b in blocks if b["type"] == "bearish" and abs(b["index"] - i) <= 15)
            fvg_count = sum(1 for f in fvgs if f["type"] == "bearish" and abs(f["index"] - i) <= 10)

            trade = Trade(
                symbol=symbol,
                direction="sell",
                entry_time=time_str,
                entry_price=entry_price,
                stop_loss=sl,
                take_profit=tp,
                risk_amount_zar=risk_zar,
                confidence=min(score / 4.0, 1.0),
                fvg_hits=fvg_count,
                ob_hits=ob_count,
            )
            trades.append(trade)

    return trades

# ─────────────────────────────────────────────────────────────
# TRADE EXECUTOR — SIMULATE WITH 1:3 R:R
# ─────────────────────────────────────────────────────────────
def simulate_trades(trades: List[Trade], df: pd.DataFrame) -> List[Trade]:
    """Simulate trade outcomes on price data."""
    results = []
    for trade in trades:
        entry_idx = df[df["time"].astype(str) == trade.entry_time].index
        if len(entry_idx) == 0:
            entry_idx = df.index[df["time"] == pd.to_datetime(trade.entry_time)]
        if len(entry_idx) == 0:
            # Find nearest
            entry_idx = [min(range(len(df)), key=lambda j: abs(
                (df["time"].iloc[j] - pd.to_datetime(trade.entry_time)).total_seconds()))]

        start = entry_idx[0]
        end = min(start + 60, len(df) - 1)  # max 60 bars held

        hit_tp = False
        hit_sl = False

        for j in range(start + 1, end + 1):
            bar = df.iloc[j]

            if trade.direction == "buy":
                if bar["low"] <= trade.stop_loss:
                    hit_sl = True
                    trade.exit_time = str(bar["time"])
                    trade.exit_price = trade.stop_loss
                    trade.pnl_zar = -trade.risk_amount_zar
                    trade.result = "loss"
                    break
                if bar["high"] >= trade.take_profit:
                    hit_tp = True
                    trade.exit_time = str(bar["time"])
                    trade.exit_price = trade.take_profit
                    trade.pnl_zar = trade.risk_amount_zar * TAKE_PROFIT_MULTIPLIER
                    trade.result = "win"
                    break
            else:  # sell
                if bar["high"] >= trade.stop_loss:
                    hit_sl = True
                    trade.exit_time = str(bar["time"])
                    trade.exit_price = trade.stop_loss
                    trade.pnl_zar = -trade.risk_amount_zar
                    trade.result = "loss"
                    break
                if bar["low"] <= trade.take_profit:
                    hit_tp = True
                    trade.exit_time = str(bar["time"])
                    trade.exit_price = trade.take_profit
                    trade.pnl_zar = trade.risk_amount_zar * TAKE_PROFIT_MULTIPLIER
                    trade.result = "win"
                    break

        if not hit_tp and not hit_sl:
            # Close at end of simulation window
            bar = df.iloc[end]
            trade.exit_time = str(bar["time"])
            trade.exit_price = bar["close"]
            if trade.direction == "buy":
                pnl_pips = (bar["close"] - trade.entry_price) / MARKETS[trade.symbol]["pip_size"]
            else:
                pnl_pips = (trade.entry_price - bar["close"]) / MARKETS[trade.symbol]["pip_size"]
            trade.pnl_zar = pnl_pips / (STOPLoss_PIPS[trade.symbol]) * trade.risk_amount_zar
            trade.result = "breakeven" if abs(pnl_pips) < 0.5 else ("win" if pnl_pips > 0 else "loss")

        results.append(trade)
    return results

# ─────────────────────────────────────────────────────────────
# ACCOUNT SIMULATION ACROSS ALL MARKETS
# ─────────────────────────────────────────────────────────────
def run_account_simulation(zar_capital: float, label: str) -> dict:
    """Run full simulation for one account."""
    equity = zar_capital
    peak_equity = zar_capital
    daily_loss_used = 0.0
    trades_log = []
    daily_returns = []
    equity_curve = [equity]
    win_count = loss_count = be_count = 0

    for symbol in ["XAUUSD", "NAS100", "US30"]:
        df = generate_ohlcv(symbol, days=60, tf="H1")
        blocks = detect_order_blocks(df)
        fvgs = detect_fvg(df)
        liq = detect_liquidity_pools(df)

        trades = generate_signals(df, symbol, blocks, fvgs, liq)
        trades = simulate_trades(trades, df)

        for t in trades:
            # Apply daily loss cap
            daily_pnl_pct = abs(t.pnl_zar) / equity if equity > 0 else 0
            if t.pnl_zar < 0 and daily_pnl_pct > DAILY_LOSS_CAP_PCT:
                t.pnl_zar = 0
                t.result = "daily_cap"
                t.exit_time = f"{t.exit_time} [daily cap hit]"

            equity += t.pnl_zar
            peak_equity = max(peak_equity, equity)
            equity_curve.append(equity)

            if t.result == "win":
                win_count += 1
            elif t.result == "loss":
                loss_count += 1
            else:
                be_count += 1

            trades_log.append(t)

    total = win_count + loss_count + be_count
    win_rate = win_count / total if total > 0 else 0

    # Metrics
    net_profit = equity - zar_capital
    max_drawdown = (peak_equity - min(equity_curve)) / peak_equity if peak_equity > 0 else 0
    sharpe = np.std(equity_curve) / (np.mean(equity_curve) + 1e-9) if len(equity_curve) > 1 else 0

    return {
        "label": label,
        "starting_capital_zar": zar_capital,
        "ending_equity_zar": round(equity, 2),
        "net_profit_zar": round(net_profit, 2),
        "net_profit_pct": round(net_profit / zar_capital * 100, 2),
        "total_trades": total,
        "wins": win_count,
        "losses": loss_count,
        "breakeven": be_count,
        "win_rate_pct": round(win_rate * 100, 1),
        "max_drawdown_pct": round(max_drawdown * 100, 2),
        "avg_r_per_trade": round(net_profit / total if total > 0 else 0, 2),
        "equity_curve": [round(e, 2) for e in equity_curve],
        "trades": trades_log,
    }

# ─────────────────────────────────────────────────────────────
# RUN MULTIPLE ACCOUNT SCENARIOS
# ─────────────────────────────────────────────────────────────
def print_trade(t: Trade) -> str:
    emoji = "✅" if t.result == "win" else "❌" if t.result == "loss" else "⚖️"
    return (f"{emoji} {t.symbol} {t.direction.upper()} | "
            f"Entry: {t.entry_price:.2f} | SL: {t.stop_loss:.2f} | TP: {t.take_profit:.2f} | "
            f"PnL: R{t.pnl_zar:.2f} | Conf: {t.confidence:.0%} | FVG: {t.fvg_hits} | OB: {t.ob_hits}")

def run_all_simulations():
    print("=" * 70)
    print("ICT-MT5 BACKTESTER — R500 ACCOUNT SIMULATION")
    print("=" * 70)

    scenarios = [
        (500, "R500 BASE ACCOUNT"),
        (500 * 2, "R1,000 DUAL ACCOUNT"),
        (500 * 4, "R2,000 PREMIUM ACCOUNT"),
    ]

    all_results = []
    for capital, label in scenarios:
        print(f"\n{'═' * 60}")
        print(f"  {label} | Starting: R{capital:,.0f}")
        print(f"{'═' * 60}")
        result = run_account_simulation(capital, label)
        all_results.append(result)

        print(f"\n  NET PROFIT   : R{result['net_profit_zar']:>8.2f}  ({result['net_profit_pct']:+.1f}%)")
        print(f"  WIN RATE     : {result['win_rate_pct']:>7.1f}%")
        print(f"  TOTAL TRADES : {result['total_trades']:>7d}")
        print(f"  W / L / BE   : {result['wins']} / {result['losses']} / {result['breakeven']}")
        print(f"  MAX DRAWDOWN : {result['max_drawdown_pct']:>7.2f}%")
        print(f"  AVG R/TRADE  : R{result['avg_r_per_trade']:>7.2f}")
        print(f"  END EQUITY   : R{result['ending_equity_zar']:>8.2f}")

        print(f"\n  SAMPLE TRADES (first 10):")
        for t in result["trades"][:10]:
            print(f"    {print_trade(t)}")

        # Equity curve (text)
        ec = result["equity_curve"]
        if len(ec) > 20:
            # Sample to ~20 points for display
            step = len(ec) // 20
            sampled = ec[::step]
        else:
            sampled = ec

        max_ec = max(ec) if ec else 1
        min_ec = min(ec) if ec else 0
        print(f"\n  EQUITY CURVE (sampled):")
        for val in sampled:
            bar_len = int((val - min_ec) / (max_ec - min_ec + 1e-9) * 30)
            bar = "█" * bar_len
            print(f"    R{val:>8.2f} | {bar}")

    # Summary comparison
    print(f"\n{'═' * 60}")
    print("  SCENARIO COMPARISON")
    print(f"{'═' * 60}")
    print(f"  {'Scenario':<25} {'Net Profit':>12} {'Return':>10} {'WinRate':>10} {'MaxDD':>10}")
    print(f"  {'-'*25} {'-'*12} {'-'*10} {'-'*10} {'-'*10}")
    for r in all_results:
        print(f"  {r['label']:<25} {f'R{r['net_profit_zar']:>10.2f}':>12} "
              f"{f'{r['net_profit_pct']:+.1f}%':>10} "
              f"{f'{r['win_rate_pct']:.1f}%':>10} "
              f"{f'{r['max_drawdown_pct']:.1f}%':>10}")

    return all_results

if __name__ == "__main__":
    results = run_all_simulations()
    print(f"\n  Backtest complete. {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("  Next step: Load into MT5 Strategy Tester for live tick validation.")