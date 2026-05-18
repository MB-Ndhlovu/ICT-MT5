# ICT-MT5 — Automated ICT Smart Money Concepts EA

> **Author:** Malibongwe Ndhlovu
> **Supervisor:** Malibongwe Ndhlovu
> **Execution:** MetaTrader 5 / MQL5
> **Target Markets:** XAUUSD, NAS100, US30
> **Risk Model:** 1% per trade, 2% daily loss cap

## Overview

ICT-MT5 is a modular Expert Advisor that converts ICT / Smart Money Concepts into a rule-based MQL5 trading engine for MetaTrader 5. The project is built to be readable, testable, and portfolio-ready rather than flashy. No magic. Just structure, rules, and risk control.

The EA combines:
- market structure detection
- order block detection
- fair value gap detection
- liquidity pool and sweep tracking
- kill zone timing filters
- premium / discount analysis
- fixed risk management
- a single signal aggregator

## Repository Layout

```text
ICT-MT5/
├── Experts/
│   └── ICT_EA.mq5
├── Include/
│   ├── ICT_MarketStructure.mqh
│   ├── ICT_OrderBlocks.mqh
│   ├── ICT_FairValueGap.mqh
│   ├── ICT_LiquidityPools.mqh
│   ├── ICT_KillZones.mqh
│   ├── ICT_PDArray.mqh
│   ├── ICT_RiskManager.mqh
│   └── ICT_SignalGenerator.mqh
├── docs/
│   ├── BACKTEST_GUIDE.md
│   └── ICT_METHODOLOGY.md
└── README.md
```

## Module Summary

| Module | Purpose | Key Dependencies |
|---|---|---|
| `ICT_MarketStructure.mqh` | Detects swing highs/lows, Break of Structure, Change of Character, and higher-timeframe alignment. | Native price series functions |
| `ICT_OrderBlocks.mqh` | Identifies bullish and bearish order blocks and tracks active, weakening, and broken zones. | `ICT_MarketStructure.mqh` |
| `ICT_FairValueGap.mqh` | Detects 3-candle fair value gaps and tracks fill, mitigation, and widening state. | Native price series functions |
| `ICT_LiquidityPools.mqh` | Tracks buy-side liquidity, sell-side liquidity, equal highs, equal lows, and sweep confirmations. | Native price series functions |
| `ICT_KillZones.mqh` | Manages London and New York kill zones, session state, and one-trade-per-session behaviour. | Native time functions |
| `ICT_PDArray.mqh` | Builds premium / discount zones, OTE windows, Fibonacci levels, and daily bias. | `ICT_MarketStructure.mqh` |
| `ICT_RiskManager.mqh` | Handles pip sizing, lot sizing, daily loss caps, drawdown state, and trade history. | Native account and symbol info |
| `ICT_SignalGenerator.mqh` | Combines all modules into a final buy / sell / none signal with confidence scoring. | All modules above |
| `ICT_EA.mq5` | Main EA shell that initialises modules, filters trades, and sends orders. | All modules above |

## Installation

1. Clone the repository.
   ```bash
   git clone https://github.com/MB-Ndhlovu/ICT-MT5.git
   ```
2. Copy the files into MetaTrader 5:
   - `.mqh` files into `MQL5/Include/`
   - `ICT_EA.mq5` into `MQL5/Experts/`
3. Restart MetaTrader 5.
4. Open `ICT_EA` from Navigator and attach it to the chart.
5. Enable Algo Trading and confirm the input settings.

## Recommended Usage

- **XAUUSD:** M5, higher noise, wider stops
- **NAS100:** H1, cleaner structure, lower frequency
- **US30:** H1, similar behaviour to NAS100

Run the EA on a VPS or a stable terminal if you want consistent session coverage. Trading from a laptop like it is 2009 is a choice, not a strategy.

## Input Parameters

| Input | Default | Description |
|---|---:|---|
| `ICT_Symbol` | `XAUUSD` | Trading symbol used by the EA. |
| `ICT_ExecTf` | `PERIOD_M5` | Execution timeframe. |
| `ICT_RiskPercent` | `1.0` | Risk per trade as a percentage of equity. |
| `ICT_MaxDailyLoss` | `2.0` | Daily loss cap in percent. |
| `ICT_MaxTrades` | `3` | Maximum number of trades per day. |
| `ICT_Lookback` | `5` | Swing / liquidity lookback for structure detection. |
| `ICT_UseLondonKZ` | `true` | Enables London kill zone logic. |
| `ICT_UseNYKZ` | `true` | Enables New York kill zone logic. |
| `ICT_UseHigherTFFilter` | `true` | Requires higher-timeframe structure alignment. |
| `ICT_MinConfidence` | `60` | Minimum signal confidence needed before entry. |
| `ICT_UseKillZoneOnly` | `true` | Hard session filter for entries. |
| `ICT_FixedLot` | `0.0` | Optional fixed lot override for testing only. |
| `ICT_DebugMode` | `true` | Prints diagnostic status to the terminal. |

## Backtesting Workflow

1. Open **MetaTrader 5 → Strategy Tester**.
2. Select `ICT_EA` as the expert.
3. Use a high-quality history source and tick data where possible.
4. Test the exact symbol / timeframe pair you intend to trade.
5. Review trade logs, session behaviour, and drawdown behaviour.

Detailed backtest guidance lives in `docs/BACKTEST_GUIDE.md`.

## Roadmap

- [x] Modular ICT detection engine
- [x] Risk-controlled EA shell
- [x] Session and liquidity logic
- [x] Portfolio-ready documentation
- [x] Backtest guide and methodology notes
- [ ] Visual chart annotations for structure, OBs, FVGs, and liquidity
- [ ] Multi-symbol optimisation presets
- [ ] Walk-forward testing report template
- [ ] Live trading journal export
- [ ] Performance dashboard for results review

## Disclaimer

This project is for educational and portfolio purposes only. It is not financial advice. Backtest thoroughly before any live deployment.