# Backtest Guide

This guide explains how to validate `ICT_EA.mq5` in the MetaTrader 5 Strategy Tester.

## 1) How to run the Strategy Tester

1. Open **MetaTrader 5**.
2. Press **Ctrl+R** or open **View → Strategy Tester**.
3. Select **Expert**: `ICT_EA`.
4. Choose the target **Symbol** and **Timeframe**:
   - `XAUUSD` on `M5`
   - `NAS100` on `H1`
   - `US30` on `H1`
5. Select **Every tick based on real ticks** if your broker history supports it.
6. Set the date range to cover enough sample size for multiple kill zones and market regimes.
7. Enable **Visual mode** if you want to inspect structure, OBs, FVGs, liquidity sweeps, and session timing.
8. Run the test and review both the report tab and the journal.

## 2) What data to use

Use the highest-quality history you can get.

Recommended order:
1. **Real ticks** from your broker or MT5 data feed
2. High-resolution tick history with low gaps
3. At minimum, a long continuous OHLC history if real ticks are not available

Recommended sample sizes:
- **XAUUSD:** at least 6 to 12 months
- **NAS100 / US30:** at least 6 to 18 months

Do not judge the EA on one week of data. That is noise wearing a fake moustache.

## 3) Key metrics to review

| Metric | What it tells you | Good sign |
|---|---|---|
| Win rate | Percentage of winning trades | Stable, not necessarily high |
| Sharpe ratio | Return relative to volatility | Above 1 is a decent starting point |
| Max drawdown | Worst equity drop from peak | Should stay within your risk tolerance |
| Profit factor | Gross profit divided by gross loss | Above 1.2 is the bare minimum worth respect |
| Average R | Average reward relative to risk | Positive and consistent |
| Trade count | Whether the system is actually trading | Enough trades for statistical confidence |

## 4) How to interpret results

### Strong result profile
- Positive expectancy
- Profit factor above 1.2
- Sharpe ratio above 1
- Drawdown controlled under the daily and total risk limits
- Trades cluster in the intended kill zones
- Signals follow the documented ICT rules instead of firing randomly

### Weak result profile
- High win rate but poor profit factor
- Frequent drawdown spikes
- Many trades outside kill zones
- Performance collapses when spread or slippage increases
- Entry logic depends on one market condition only

### What matters most
A high win rate by itself is not enough. A system can win often and still lose money if the average loss is larger than the average win. The real question is whether the EA produces positive expectancy after spread, commission, and slippage.

## 5) Suggested validation checklist

- Confirm the EA respects `ICT_MaxDailyLoss`
- Confirm the EA stops after the configured number of trades
- Confirm kill-zone filtering works as expected
- Confirm the confidence threshold blocks weak setups
- Confirm results are still acceptable when commission and spread are included
- Compare performance across at least two symbols before calling it robust

## 6) Reporting format

When you review a test, record:
- symbol
- timeframe
- data range
- modelling quality
- win rate
- Sharpe ratio
- max drawdown
- profit factor
- trade count
- notes on behaviour inside kill zones and around liquidity sweeps

That gives you a proper audit trail instead of a pile of vibes.