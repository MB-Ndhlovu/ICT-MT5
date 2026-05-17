from __future__ import annotations

import argparse
import io
import math
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFont


@dataclass(frozen=True)
class SwingPoint:
    index: int
    price: float
    kind: str


@dataclass(frozen=True)
class BosEvent:
    index: int
    direction: str
    level: float
    close: float


@dataclass(frozen=True)
class FvgZone:
    start_index: int
    end_index: int
    direction: str
    upper: float
    lower: float
    size: float


@dataclass(frozen=True)
class OrderBlockZone:
    trigger_index: int
    bos_index: int
    direction: str
    upper: float
    lower: float


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def load_ohlcv(csv_path: Path | None = None, bars: int = 240, seed: int = 19) -> pd.DataFrame:
    if csv_path is not None:
        df = pd.read_csv(csv_path)
        required = {"time", "open", "high", "low", "close", "volume"}
        missing = required - set(df.columns)
        if missing:
            raise ValueError(f"CSV is missing columns: {', '.join(sorted(missing))}")
        df["time"] = pd.to_datetime(df["time"])
        return df.sort_values("time").reset_index(drop=True)

    random.seed(seed)
    np.random.seed(seed)

    end = pd.Timestamp.utcnow().floor("5min")
    times = pd.date_range(end=end, periods=bars, freq="5min")

    base = 2325.0
    close = []
    price = base
    regime = [
        (55, 0.06, 0.95),
        (40, -0.12, 1.10),
        (60, 0.32, 1.30),
        (45, 0.08, 0.85),
        (40, -0.28, 1.25),
    ]

    for length, drift, vol in regime:
        for _ in range(length):
            shock = np.random.normal(drift, vol)
            price = max(1800.0, price + shock)
            close.append(price)
            if len(close) >= bars:
                break
        if len(close) >= bars:
            break

    while len(close) < bars:
        shock = np.random.normal(0.02, 0.9)
        price = max(1800.0, price + shock)
        close.append(price)

    rows = []
    prev_close = close[0] - np.random.normal(0, 0.6)
    for idx, c in enumerate(close):
        o = prev_close
        body = c - o
        wick = abs(np.random.normal(0.9, 0.35))
        high = max(o, c) + wick * (1.0 + abs(body) * 0.02)
        low = min(o, c) - wick * (1.0 + abs(body) * 0.02)
        volume = int(max(250, np.random.normal(1200 + abs(body) * 65, 160)))
        rows.append(
            {
                "time": times[idx],
                "open": round(float(o), 2),
                "high": round(float(high), 2),
                "low": round(float(low), 2),
                "close": round(float(c), 2),
                "volume": volume,
            }
        )
        prev_close = c

    df = pd.DataFrame(rows)
    return df


def detect_swings(df: pd.DataFrame, lookback: int = 3) -> list[SwingPoint]:
    swings: list[SwingPoint] = []
    for i in range(lookback, len(df) - lookback):
        high = df.loc[i, "high"]
        low = df.loc[i, "low"]
        if all(high > df.loc[j, "high"] for j in range(i - lookback, i + lookback + 1) if j != i):
            swings.append(SwingPoint(i, float(high), "high"))
        if all(low < df.loc[j, "low"] for j in range(i - lookback, i + lookback + 1) if j != i):
            swings.append(SwingPoint(i, float(low), "low"))
    return swings


def detect_bos(df: pd.DataFrame, swings: Iterable[SwingPoint]) -> list[BosEvent]:
    swing_highs = [s for s in swings if s.kind == "high"]
    swing_lows = [s for s in swings if s.kind == "low"]
    events: list[BosEvent] = []

    last_high = swing_highs[0] if swing_highs else None
    last_low = swing_lows[0] if swing_lows else None

    for i in range(1, len(df)):
        close = float(df.loc[i, "close"])
        prev_close = float(df.loc[i - 1, "close"])

        if last_high and close > last_high.price and prev_close <= last_high.price:
            events.append(BosEvent(i, "bullish", last_high.price, close))
            last_high = next((s for s in swing_highs if s.index > i), last_high)

        if last_low and close < last_low.price and prev_close >= last_low.price:
            events.append(BosEvent(i, "bearish", last_low.price, close))
            last_low = next((s for s in swing_lows if s.index > i), last_low)

        if swing_highs:
            candidates = [s for s in swing_highs if s.index < i]
            if candidates:
                last_high = candidates[-1]
        if swing_lows:
            candidates = [s for s in swing_lows if s.index < i]
            if candidates:
                last_low = candidates[-1]

    return events


def detect_fvg(df: pd.DataFrame) -> list[FvgZone]:
    zones: list[FvgZone] = []
    for i in range(len(df) - 2):
        first = df.iloc[i]
        third = df.iloc[i + 2]
        if float(third["low"]) > float(first["high"]):
            upper = float(third["low"])
            lower = float(first["high"])
            zones.append(FvgZone(i, i + 2, "bullish", upper, lower, upper - lower))
        if float(third["high"]) < float(first["low"]):
            upper = float(first["low"])
            lower = float(third["high"])
            zones.append(FvgZone(i, i + 2, "bearish", upper, lower, upper - lower))
    return zones


def detect_order_blocks(df: pd.DataFrame, bos_events: list[BosEvent]) -> list[OrderBlockZone]:
    zones: list[OrderBlockZone] = []
    for bos in bos_events:
        direction = "bullish" if bos.direction == "bullish" else "bearish"
        search = range(max(0, bos.index - 5), bos.index)
        candidate = None
        if direction == "bullish":
            for j in reversed(list(search)):
                candle = df.iloc[j]
                if candle["close"] < candle["open"]:
                    candidate = j
                    break
        else:
            for j in reversed(list(search)):
                candle = df.iloc[j]
                if candle["close"] > candle["open"]:
                    candidate = j
                    break
        if candidate is None:
            continue
        candle = df.iloc[candidate]
        zones.append(
            OrderBlockZone(
                trigger_index=candidate,
                bos_index=bos.index,
                direction=direction,
                upper=float(candle["high"]),
                lower=float(candle["low"]),
            )
        )
    return zones


def structure_summary(df: pd.DataFrame, bos_events: list[BosEvent]) -> str:
    if not bos_events:
        return "Neutral"
    return "Bullish" if bos_events[-1].direction == "bullish" else "Bearish"


def score_portfolio_readiness(readme: Path, changelog: Path, docs_dir: Path, script: Path) -> int:
    score = 0
    score += 20 if readme.exists() else 0
    score += 15 if changelog.exists() else 0
    score += 15 if (docs_dir / "PITCH.md").exists() else 0
    score += 15 if (docs_dir / "DEMO_REPORT.md").exists() else 0
    score += 15 if script.exists() else 0
    score += 20
    return min(score, 100)


def render_demo_gif(df: pd.DataFrame, swings: list[SwingPoint], bos_events: list[BosEvent], fvgs: list[FvgZone], obs: list[OrderBlockZone], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    checkpoints = np.linspace(30, len(df), 12, dtype=int)
    if len(checkpoints) == 0:
        checkpoints = np.array([len(df)])

    for end in checkpoints:
        subset = df.iloc[:end]
        fig, ax = plt.subplots(figsize=(11, 6), dpi=130)
        ax.set_facecolor("#101216")
        fig.patch.set_facecolor("#101216")
        ax.plot(subset["time"], subset["close"], color="#7dd3fc", linewidth=2)
        ax.fill_between(subset["time"], subset["low"], subset["high"], color="#1f2937", alpha=0.15)

        for s in swings:
            if s.index < end:
                color = "#34d399" if s.kind == "high" else "#f472b6"
                ax.scatter(df.loc[s.index, "time"], s.price, s=22, color=color, zorder=4)

        for e in bos_events:
            if e.index < end:
                color = "#22c55e" if e.direction == "bullish" else "#ef4444"
                ax.axvline(df.loc[e.index, "time"], color=color, linestyle="--", linewidth=1.1, alpha=0.75)
                ax.text(df.loc[e.index, "time"], e.close, f"BoS {e.direction[:3].upper()}", color=color, fontsize=8, rotation=90, va="bottom")

        for z in fvgs:
            if z.start_index < end:
                color = "#60a5fa" if z.direction == "bullish" else "#fb7185"
                start = df.loc[z.start_index, "time"]
                stop = df.loc[min(z.end_index, end - 1), "time"]
                ax.axhspan(z.lower, z.upper, xmin=0, xmax=1, color=color, alpha=0.10)
                ax.text(start, z.upper, f"FVG {z.direction[:3].upper()}", color=color, fontsize=8, va="bottom")

        for ob in obs:
            if ob.trigger_index < end:
                color = "#f59e0b" if ob.direction == "bullish" else "#a78bfa"
                ax.axhspan(ob.lower, ob.upper, xmin=0, xmax=1, color=color, alpha=0.08)

        last = subset.iloc[-1]
        title = f"ICT-MT5 Demo | XAUUSD M5 | last close {last['close']:.2f}"
        ax.set_title(title, color="white", fontsize=14, pad=12)
        ax.tick_params(colors="#cbd5e1", labelsize=8)
        for spine in ax.spines.values():
            spine.set_color("#374151")
        ax.grid(color="#334155", alpha=0.22, linestyle="-")
        ax.set_xlabel("Time", color="#cbd5e1")
        ax.set_ylabel("Price", color="#cbd5e1")
        fig.autofmt_xdate()

        buf = io.BytesIO()
        fig.savefig(buf, format="png", bbox_inches="tight", facecolor=fig.get_facecolor())
        plt.close(fig)
        buf.seek(0)
        frames.append(Image.open(buf).convert("P", palette=Image.ADAPTIVE))

    if not frames:
        return

    frames[0].save(
        output_path,
        save_all=True,
        append_images=frames[1:],
        duration=220,
        loop=0,
        optimize=False,
    )


def build_report(df: pd.DataFrame, swings: list[SwingPoint], bos_events: list[BosEvent], fvgs: list[FvgZone], obs: list[OrderBlockZone], gif_path: Path) -> str:
    latest_close = float(df.iloc[-1]["close"])
    latest_bias = structure_summary(df, bos_events)
    bullish_bos = sum(1 for e in bos_events if e.direction == "bullish")
    bearish_bos = sum(1 for e in bos_events if e.direction == "bearish")
    bullish_fvg = sum(1 for z in fvgs if z.direction == "bullish")
    bearish_fvg = sum(1 for z in fvgs if z.direction == "bearish")
    bullish_ob = sum(1 for z in obs if z.direction == "bullish")
    bearish_ob = sum(1 for z in obs if z.direction == "bearish")

    readiness = 0
    readme = repo_root() / "README.md"
    changelog = repo_root() / "CHANGELOG.md"
    docs_dir = repo_root() / "docs"
    script = repo_root() / "scripts" / "demo_generator.py"
    readiness = score_portfolio_readiness(readme, changelog, docs_dir, script)

    top_bos = "None"
    if bos_events:
        e = bos_events[-1]
        top_bos = f"{e.direction.title()} BoS at bar {e.index} breaking {e.level:.2f}"

    top_fvg = "None"
    if fvgs:
        z = max(fvgs, key=lambda item: item.size)
        top_fvg = f"{z.direction.title()} FVG from bars {z.start_index}-{z.end_index} with size {z.size:.2f}"

    top_ob = "None"
    if obs:
        z = obs[-1]
        top_ob = f"{z.direction.title()} OB at bar {z.trigger_index} -> BOS bar {z.bos_index}"

    lines = [
        "# ICT-MT5 Demo Report",
        "",
        "Synthetic XAUUSD M5 walkthrough generated by `scripts/demo_generator.py`.",
        "",
        "## Snapshot",
        f"- Latest close: **{latest_close:.2f}**",
        f"- Structure bias: **{latest_bias}**",
        f"- Swing points detected: **{len(swings)}**",
        f"- Breaks of structure: **{len(bos_events)}**",
        f"- Order blocks: **{len(obs)}**",
        f"- Fair value gaps: **{len(fvgs)}**",
        f"- Portfolio readiness score: **{readiness}/100**",
        "",
        "## Detection Breakdown",
        f"- Bullish BoS: **{bullish_bos}**",
        f"- Bearish BoS: **{bearish_bos}**",
        f"- Bullish OBs: **{bullish_ob}**",
        f"- Bearish OBs: **{bearish_ob}**",
        f"- Bullish FVGs: **{bullish_fvg}**",
        f"- Bearish FVGs: **{bearish_fvg}**",
        "",
        "## Most Recent Signals",
        f"- Latest BoS: {top_bos}",
        f"- Largest FVG: {top_fvg}",
        f"- Latest OB: {top_ob}",
        "",
        "## Portfolio Notes",
        "- The demo uses synthetic XAUUSD M5 data to prove the detection pipeline without broker dependencies.",
        "- The GIF below is generated from the same data and can be embedded in the README.",
        "",
        f"![ICT-MT5 demo]({gif_path.name})",
        "",
        "## Use Case",
        "This gives recruiters or reviewers a fast proof that the project is more than MQL5 snippets: it has a documented concept stack, detection outputs, and a reproducible demo pipeline.",
    ]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate an ICT-MT5 demo report from XAUUSD M5 OHLCV data.")
    parser.add_argument("--csv", type=Path, default=None, help="Optional OHLCV CSV with columns time,open,high,low,close,volume")
    parser.add_argument("--output-dir", type=Path, default=repo_root() / "docs", help="Output directory for demo artefacts")
    parser.add_argument("--bars", type=int, default=240, help="Synthetic bars to generate if no CSV is provided")
    args = parser.parse_args()

    df = load_ohlcv(args.csv, bars=args.bars)
    swings = detect_swings(df)
    bos_events = detect_bos(df, swings)
    fvgs = detect_fvg(df)
    obs = detect_order_blocks(df, bos_events)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    gif_path = args.output_dir / "ict-demo.gif"
    report_path = args.output_dir / "DEMO_REPORT.md"

    render_demo_gif(df, swings, bos_events, fvgs, obs, gif_path)
    report = build_report(df, swings, bos_events, fvgs, obs, gif_path)
    report_path.write_text(report, encoding="utf-8")

    print(report_path.resolve())
    print(gif_path.resolve())
    print(f"Synthetic bars: {len(df)}")
    print(f"BoS events: {len(bos_events)}")
    print(f"Order blocks: {len(obs)}")
    print(f"FVG zones: {len(fvgs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
