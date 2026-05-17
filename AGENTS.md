# Bantu-OS — ICT Automation Project

## Project: ICT Trading EA for MT5 (MQL5)

**Supervisor:** User (Malibongwe Ndhlovu) — report format
**Markets:** XAUUSD, NAS100, US30
**Risk:** 1% per trade | Daily loss cap: -2%
**Execution:** MQL5 EA via MetaTrader 5

## Architecture

```
ICT_EA.mq5                    ← Main EA (shell)
├── Include/ICT_MarketStructure.mqh   ✅ SUBMITTED
├── Include/ICT_OrderBlocks.mqh       ← Next
├── Include/ICT_FairValueGap.mqh
├── Include/ICT_LiquidityPools.mqh
├── Include/ICT_KillZones.mqh
├── Include/ICT_PDArray.mqh
├── Include/ICT_RiskManager.mqh
└── Include/ICT_SignalGenerator.mqh   ← Brings all modules together
```

## Status

- [x] ICT_MarketStructure — SUBMITTED
- [ ] ICT_OrderBlocks — Pending
- [ ] ICT_FairValueGap — Pending
- [ ] ICT_LiquidityPools — Pending
- [ ] ICT_KillZones — Pending
- [ ] ICT_PDArray — Pending
- [ ] ICT_RiskManager — Pending
- [ ] ICT_SignalGenerator — Pending
- [ ] ICT_EA (main shell) — Pending
- [ ] Backtesting guide — Pending

## Market-Specific Settings

| Market    | Timeframe | Lookback | Notes                        |
|-----------|-----------|----------|------------------------------|
| XAUUSD    | M5        | 3-5      | High noise, wider stops      |
| NAS100    | H1        | 8-12     | Slower structure, avoid M1   |
| US30      | H1        | 8-12     | Correlates with DXY + SPX    |

## Supervisor Preferences

- Report format: supervisor style (design decisions, flags, testing checklist)
- Build directly + explain simultaneously
- No fluff — direct, technical, honest
- 1% risk per trade, 0.5% optional tightening
- Starting capital: irrelevant (R-based system)