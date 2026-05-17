# Contributing to ICT-MT5

All contributions must be submitted as pull requests to the `main` branch.

## Pull Request Process

1. Fork the repository and create a feature branch from `main`
2. Ensure all modules compile without errors in MetaEditor
3. Add new modules with full header documentation (author, supervisor, date, purpose)
4. Update README.md to reflect any new files or architectural changes
5. Run a backtest with your changes before submitting the PR
6. All PRs require a description explaining the change and its rationale

## Code Standards

- All `.mqh` files must include header with: Author, Supervisor, Date, Purpose
- All enums and structs must be documented
- Debug prints must be gated behind `ICT_DebugMode`
- No hardcoded magic numbers — use named constants or inputs
- 1% risk per trade is the hard cap — no override allowed in any module
- No indicator anti-patterns: no repainting, no future-leaking buffers

## Architecture Rules

- Each module is standalone — no circular dependencies
- `ICT_MarketStructure.mqh` is the base dependency — all others may reference it
- `ICT_SignalGenerator.mqh` is the aggregator — references all other modules
- `ICT_EA.mq5` is the only file that references everything — it is the entry point
- Kill Zones are a hard filter — setting `ICT_UseKillZoneOnly = false` still requires KZ active by default