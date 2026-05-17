# ICT-MT5

## Automated ICT Smart Money Concepts EA for MetaTrader 5

ICT-MT5 is a rule-based Expert Advisor that turns ICT / Smart Money Concepts into a structured MQL5 execution engine. It is built to detect market structure shifts, order blocks, fair value gaps, liquidity pools, kill zones, and premium/discount alignment, then combine them into a filtered trade signal.

### What it does
- Detects BoS and ChoCh-style market structure events
- Identifies order blocks and fair value gaps
- Tracks liquidity pools and session kill zones
- Uses a daily premium/discount framework for bias
- Applies fixed risk controls with a daily loss cap

### Why it matters
Most trading projects stop at theory. This one shows implementation discipline: modular code, risk control, session logic, and a reproducible demo pipeline. It is portfolio-friendly because it demonstrates both domain knowledge and software structure.

### Tech stack
- MQL5 for MetaTrader 5 execution
- Modular `.mqh` include files
- Python demo pipeline for synthetic OHLCV analysis
- Markdown documentation for review and onboarding

### Portfolio value
- Shows algorithmic thinking under constraints
- Demonstrates trading-system design, not just indicator cloning
- Easy to explain in interviews, applications, or a GitHub profile

### Repository link
- GitHub: `https://github.com/MB-Ndhlovu/ICT-MT5`
