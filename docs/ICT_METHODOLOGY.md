# ICT Methodology

## What ICT is

ICT stands for **Inner Circle Trader**. In practice, it is a market-structure-first way of reading price action that focuses on where liquidity sits, where institutions may be active, and when price is most likely to move aggressively. The idea is not to predict every candle. It is to build an edge around structure, timing, and liquidity.

## Core concepts implemented in this project

| Concept | How it is used |
|---|---|
| Market structure | Detects swing highs/lows, Break of Structure, and Change of Character |
| Liquidity | Tracks buy-side liquidity, sell-side liquidity, equal highs, equal lows, and sweep behaviour |
| Order blocks | Identifies the last opposing candle before displacement and monitors mitigation |
| Fair value gaps | Detects 3-candle imbalances and tracks fill / mitigation state |
| Kill zones | Restricts trading to high-probability session windows |
| Premium / discount | Uses daily Fibonacci range to separate buy-side and sell-side bias |
| OTE | Highlights the 62% to 79% retracement area for entries |
| Risk control | Fixes risk per trade and enforces a daily loss cap |

## Why the modules are built this way

### 1) `ICT_MarketStructure.mqh`
This is the foundation. If structure is wrong, everything else becomes decorative nonsense. The module uses swing logic and higher-timeframe alignment so the EA can separate continuation from reversal.

### 2) `ICT_OrderBlocks.mqh`
Order blocks are only useful if they are treated as zones with state. This module tracks whether a block is pending, active, weakening, or broken, which keeps the EA from treating every candle like a sacred signal.

### 3) `ICT_FairValueGap.mqh`
FVGs represent price imbalance. The module tracks not just detection, but fill ratio, widening, and mitigation, because a gap that has already been filled is not the same as a fresh imbalance.

### 4) `ICT_LiquidityPools.mqh`
Liquidity is the bait. This module tracks swing-based pools and equal highs / lows, then watches for sweeps. That supports entries only after price has done the typical stop-hunt behaviour ICT traders care about.

### 5) `ICT_KillZones.mqh`
Timing matters. The project only wants to trade during the most meaningful windows, especially London and New York session activity. Session state is tracked so the EA can behave like a specialist rather than a random button.

### 6) `ICT_PDArray.mqh`
Premium / discount logic gives the EA a directional framework. The module computes the daily range, 50% midpoint, and OTE bands so the EA can distinguish between price being cheap, expensive, or in the middle of nowhere.

### 7) `ICT_RiskManager.mqh`
Without risk control, strategy quality becomes irrelevant. This module standardises pip sizing across the supported symbols, sizes positions from equity, and halts trading when the daily loss cap is reached.

### 8) `ICT_SignalGenerator.mqh`
This is the filter stack. It does not invent a strategy. It checks whether the other modules agree, scores the setup, and only returns a buy or sell when the conditions are strong enough.

## Design philosophy

The EA is intentionally conservative:
- one signal engine
- no future-leaking logic
- no repaint-heavy shortcuts
- fixed risk limits
- session filtering by default
- confirm-before-entry behaviour

That makes it easier to explain, backtest, and defend in a portfolio context.

## What this is not

- Not a discretionary chart-reading replacement
- Not a guaranteed edge machine
- Not a machine-learning model pretending to be wisdom
- Not a high-frequency system

It is a structured ICT implementation that can be tested, audited, and improved over time.