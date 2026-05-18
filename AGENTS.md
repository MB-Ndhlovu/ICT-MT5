# Bantu-OS — ICT Automation Project

## Project: ICT Trading EA for MT5 (MQL5)

**Supervisor:** Malibongwe Ndhlovu
**Markets:** XAUUSD, NAS100, US30
**Risk:** 1% per trade | Daily loss cap: -2%
**Execution:** MQL5 EA via MetaTrader 5

## Architecture

```text
Experts/ICT_EA.mq5                  ← Main EA shell
Include/ICT_MarketStructure.mqh     ← Structure engine
Include/ICT_OrderBlocks.mqh         ← Order block engine
Include/ICT_FairValueGap.mqh        ← FVG engine
Include/ICT_LiquidityPools.mqh      ← Liquidity engine
Include/ICT_KillZones.mqh           ← Session timing engine
Include/ICT_PDArray.mqh             ← Premium / discount engine
Include/ICT_RiskManager.mqh         ← Risk and sizing engine
Include/ICT_SignalGenerator.mqh     ← Signal aggregation engine
```

## Current Status

- [x] ICT_MarketStructure — complete
- [x] ICT_OrderBlocks — complete
- [x] ICT_FairValueGap — complete
- [x] ICT_LiquidityPools — complete
- [x] ICT_KillZones — complete
- [x] ICT_PDArray — complete
- [x] ICT_RiskManager — complete
- [x] ICT_SignalGenerator — complete
- [x] ICT_EA (main shell) — complete
- [x] README.md — updated
- [x] BACKTEST_GUIDE.md — updated
- [x] ICT_METHODOLOGY.md — updated
- [x] CHANGELOG.md — updated

## Market-Specific Settings

| Market | Timeframe | Lookback | Notes |
|---|---|---:|---|
| XAUUSD | M5 | 3–5 | High noise, wider stops |
| NAS100 | H1 | 8–12 | Slower structure, avoid M1 |
| US30 | H1 | 8–12 | Correlates with DXY + SPX |

## Supervisor Preferences

- Report format: supervisor style — design decisions, flags, testing checklist
- Build directly and explain simultaneously
- No fluff. Direct, technical, honest.
- 1% risk per trade, 0.5% optional tightening
- Starting capital is irrelevant; use an R-based system

## Notes

Keep this file compact and current. It is a routing map, not a transcript log.