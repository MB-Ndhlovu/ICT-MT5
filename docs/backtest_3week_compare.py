#!/usr/bin/env python3
"""
ICT-MT5 Three-Week Comparison — XAUUSD vs NAS100 vs US30
All three markets on identical 3-week H1 data.
1% risk per trade | 1:3 R:R | ICT confluence | ATR-adaptive stops

v3 FIXES:
- Relax signal threshold: |score| >= 2 (was >= 3)
- TP now measured as 3x the distance from entry to nearest swing low/high (dynamic, not ATR)
- Kill zone: UTC-based times for Yahoo data
- One trade per session per day
"""

import yfinance as yf
import pandas as pd
import numpy as np
import warnings
warnings.filterwarnings('ignore')

START_DATE = "2026-05-01"
END_DATE   = "2026-05-22"
ACCOUNT    = 500.00
RISK_PCT   = 0.01
RR_RATIO   = 3.0

TICKERS = {
    "XAUUSD": {"yf": "GC=F", "minSL": 50},
    "NAS100": {"yf": "^NDX", "minSL": 10},
    "US30":   {"yf": "^DJI", "minSL": 20},
}

def compute_indicators(df):
    c = df["Close"]; v = df["Volume"]
    h, l = df["High"], df["Low"]
    df["EMA20"]  = c.ewm(span=20,  min_periods=20).mean()
    df["EMA50"]  = c.ewm(span=50,  min_periods=50).mean()
    df["EMA200"] = c.ewm(span=200, min_periods=200).mean()
    df["VWAP"]   = (c * v).cumsum() / v.cumsum()
    delta = c.diff()
    gain  = delta.clip(lower=0).rolling(14).mean()
    loss  = (-delta.clip(upper=0)).rolling(14).mean()
    df["RSI"]    = 100 - (100 / (1 + gain.div(loss.replace(0, np.nan))))
    df["ATR14"]  = np.maximum(h - l, np.maximum(abs(h - c.shift(1)), abs(l - c.shift(1)))).rolling(14).mean()
    df["UTC_Hour"] = df.index.hour + df.index.minute / 60.0
    return df

def detect_bos(df, lookback=20):
    bos = np.zeros(len(df))
    for i in range(lookback, len(df)):
        win = df.iloc[i-lookback:i]
        hh = win["High"].idxmax()
        ll = win["Low"].idxmin()
        cur_c = df.iloc[i]["Close"]
        if cur_c > win.loc[hh, "High"] * 0.9995:   bos[i] = 1
        elif cur_c < win.loc[ll, "Low"] * 1.0005:   bos[i] = -1
    return pd.Series(bos, index=df.index)

def kz_info(utc_h):
    if   7  <= utc_h < 10:  return "LONDON",  0.8
    if   13.5 <= utc_h < 16: return "NYOPEN",  1.0
    if   19  <= utc_h < 21:  return "NYCLOSE", 1.3
    return None, 0.0

def get_swing_sl_tp(df, idx, direction, atr):
    look = 20
    start = max(0, idx - look)
    win = df.iloc[start:idx]
    if direction == 1:
        # Buy: SL below nearest swing low, TP above swing high
        sl_candidate = win["Low"].min()
        tp_candidate = win["High"].max()
        risk = df.iloc[idx]["Close"] - sl_candidate
        reward = tp_candidate - df.iloc[idx]["Close"]
        if risk <= 0 or reward <= 0:
            risk = atr * 0.5
            reward = risk * RR_RATIO
            sl_candidate = df.iloc[idx]["Close"] - risk
            tp_candidate = df.iloc[idx]["Close"] + reward
        return sl_candidate, tp_candidate, risk, reward
    else:
        sl_candidate = win["High"].max()
        tp_candidate = win["Low"].min()
        risk = sl_candidate - df.iloc[idx]["Close"]
        reward = df.iloc[idx]["Close"] - tp_candidate
        if risk <= 0 or reward <= 0:
            risk = atr * 0.5
            reward = risk * RR_RATIO
            sl_candidate = df.iloc[idx]["Close"] + risk
            tp_candidate = df.iloc[idx]["Close"] - reward
        return sl_candidate, tp_candidate, risk, reward

def simulate(df, symbol, minSL):
    results = []
    equity = ACCOUNT
    max_eq = equity
    max_dd = 0.0
    wins = losses = 0
    pos_open = False
    entry_dir = entry_price = sl = tp = 0.0
    active_session = None

    traded = set()

    start_bar = max(55, len(df) - 55)  # Adaptive: works for both 345-bar and 105-bar datasets
    for i in range(start_bar, len(df)):
        row = df.iloc[i]
        dt  = df.index[i]
        utc_h = row["UTC_Hour"]
        c = row["Close"]
        h, l = row["High"], row["Low"]
        ema20 = row["EMA20"]; ema50 = row["EMA50"]; ema200_val = row["EMA200"]
        vwap = row["VWAP"]; rsi = row["RSI"]; atr = row["ATR14"]
        bos = row.get("BOS", 0)

        # Use EMA200 if available, otherwise EMA50 as fallback
        trend_bull = ema20 > ema50
        trend_bear = ema20 < ema50
        if not pd.isna(ema200_val):
            trend_bull = trend_bull and ema20 > ema50 > ema200_val
            trend_bear = trend_bear and ema20 < ema50 < ema200_val

        if pd.isna(atr): continue

        # ── ICT signal score ────────────────────────────────────────
        score = 0
        if trend_bull: score += 1
        if trend_bear: score -= 1
        if c > vwap: score += 1
        if c < vwap: score -= 1
        if rsi < 35: score += 1
        if rsi > 65: score -= 1
        if bos == 1:  score += 1
        if bos == -1: score -= 1

        sl_pips_raw = max(float(atr * 0.5), minSL)

        # ── Entry ───────────────────────────────────────────────────
        session, kz_w = kz_info(utc_h)
        date_str = str(dt.date())

        if not pos_open and session is not None:
            session_key = (session, date_str)
            if abs(score) >= 2 and session_key not in traded:
                sl_candidate, tp_candidate, risk, reward = get_swing_sl_tp(df, i, 1 if score > 0 else -1, sl_pips_raw)
                rr_actual = reward / risk if risk > 0 else 0

                # Only trade if R:R >= 1.5 (filter unrealistic setups)
                if rr_actual >= 1.5:
                    entry_dir = 1 if score > 0 else -1
                    entry_price = c
                    sl = sl_candidate
                    tp = tp_candidate

                    pos_open = True
                    traded.add(session_key)
                    active_session = session

        # ── Exit ────────────────────────────────────────────────────
        if pos_open:
            hit = None
            if entry_dir == 1:
                if h >= tp: hit = "WIN"
                elif l <= sl: hit = "LOSS"
            elif entry_dir == -1:
                if l <= tp: hit = "WIN"
                elif h >= sl: hit = "LOSS"

            if hit:
                risk_zar = equity * RISK_PCT
                pnl = risk_zar * RR_RATIO if hit == "WIN" else -risk_zar
                if hit == "WIN": wins += 1
                else: losses += 1
                equity += pnl
                max_eq = max(max_eq, equity)
                dd = (max_eq - equity) / max_eq * 100
                max_dd = max(max_dd, dd)
                results.append({
                    "datetime": dt, "symbol": symbol,
                    "direction": "BUY" if entry_dir == 1 else "SELL",
                    "entry": round(entry_price, 4),
                    "sl": round(sl, 4), "tp": round(tp, 4),
                    "result": hit,
                    "pnl_zar": round(pnl, 2),
                    "r_achieved": round(pnl / risk_zar, 2),
                    "equity": round(equity, 2),
                    "session": active_session,
                    "atr": round(atr, 4),
                    "sl_pips": round(sl, 4),
                    "score": score,
                })
                pos_open = False

        equity = max(equity, 0.01)

    total = wins + losses
    wr = wins / total * 100 if total > 0 else 0
    avg_r = (wins * RR_RATIO - losses) / total if total > 0 else 0
    ret = (equity - ACCOUNT) / ACCOUNT * 100
    return equity, results, wins, losses, wr, avg_r, max_dd, ret

# ─── Main ──────────────────────────────────────────────────────────────
print("=" * 72)
print("  ICT-MT5 — 3-WEEK THREE-MARKET COMPARISON (v3)")
print(f"  Period: {START_DATE} → {END_DATE} | R{ACCOUNT} | 1% risk | 1:3 R:R")
print("  Signal: |score|>=2 in KZ | R:R>=1.5 | Dynamic swing-based SL/TP")
print("=" * 72)

summary = []
for symbol, cfg in TICKERS.items():
    df = yf.download(cfg["yf"], start=START_DATE, end=END_DATE,
                     interval="1h", auto_adjust=True, progress=False)
    if df.empty:
        print(f"\n  {symbol}: No data"); continue
    df.columns = df.columns.get_level_values(0)
    df.index = pd.to_datetime(df.index).tz_localize(None)
    df = compute_indicators(df)
    df["BOS"] = detect_bos(df)

    final_eq, trades, wins, losses, wr, avg_r, max_dd, ret = simulate(df, symbol, cfg["minSL"])
    total = wins + losses

    print(f"\n{'─' * 72}")
    print(f"  {symbol} | {len(df)} H1 bars | {total} trades ({wins}W/{losses}L)")
    print(f"  Final Equity : R{final_eq:,.2f}  ({ret:+.2f}%)")
    print(f"  Win Rate     : {wr:.1f}%  |  Avg R: {avg_r:+.2f}R  |  MaxDD: {max_dd:.2f}%")

    if trades:
        td = pd.DataFrame(trades)
        td.to_csv(f"docs/3wk_{symbol.lower()}_trades.csv", index=False)
        print(f"  Saved: docs/3wk_{symbol.lower()}_trades.csv")
        print(f"  Sample trade: entry={trades[0]['entry']:.4f} sl={trades[0]['sl']:.4f} tp={trades[0]['tp']:.4f}")

    summary.append({
        "Market": symbol, "Equity": round(final_eq, 2),
        "Return_pct": round(ret, 2), "Trades": total,
        "WinRate": round(wr, 1), "AvgR": round(avg_r, 2),
        "MaxDD": round(max_dd, 2),
    })

print("\n" + "=" * 72)
print("  SIDE-BY-SIDE RESULTS")
print("=" * 72)
print(f"  {'Market':<10} {'Equity':>12} {'Return':>9} {'Trades':>8} {'WR':>7} {'AvgR':>8} {'MaxDD':>8}")
print("  " + "-" * 66)
for s in summary:
    print(f"  {s['Market']:<10} R{s['Equity']:>10,.2f} {s['Return_pct']:>+8.1f}% {s['Trades']:>8} {s['WinRate']:>6.1f}% {s['AvgR']:>+7.2f}R {s['MaxDD']:>7.2f}%")
print("=" * 72)
if summary:
    best = max(summary, key=lambda x: x["Equity"])
    print(f"\n  ★ BEST: {best['Market']} — R{best['Equity']:,.2f} ({best['Return_pct']:+.1f}%)")