//+------------------------------------------------------------------+
//|  ICT Smart Money Concepts EA                                     |
//|  File: ICT_EA.mq5                                                 |
//|  Author: Malibongwe Ndhlovu                                       |
//|  Supervisor: Ben JARVIS AI                                        |
//|  Date: 2026-05-17                                                 |
//|  Description: ICT-based automated trading for XAUUSD, NAS100, US30|
//|  Risk: 1% per trade | Daily Cap: -2% | Target: 1:3 RR            |
//+------------------------------------------------------------------+
#property copyright "Malibongwe Ndhlovu"
#property link      "https://github.com/MB-Ndhlovu/ICT-MT5"
#property version   "1.00"
#property strict

// Include all ICT modules
#include <ICT_MarketStructure.mqh>
#include <ICT_OrderBlocks.mqh>
#include <ICT_FairValueGap.mqh>
#include <ICT_LiquidityPools.mqh>
#include <ICT_KillZones.mqh>
#include <ICT_PDArray.mqh>
#include <ICT_RiskManager.mqh>
#include <ICT_SignalGenerator.mqh>

//+------------------------------------------------------------------+
//| INPUTS — User Configurable                                        |
//+------------------------------------------------------------------+
input group "=== SYMBOL & TIMEFRAME ==="
input string   ICT_Symbol       = "XAUUSD";          // Trading Symbol
input ENUM_TIMEFRAMES ICT_ExecTf = PERIOD_M5;       // Execution Timeframe

input group "=== RISK MANAGEMENT ==="
input double ICT_RiskPercent   = 1.0;               // Risk Per Trade (%)
input double ICT_MaxDailyLoss = 2.0;                // Daily Loss Cap (%)
input int    ICT_MaxTrades     = 3;                  // Max Trades Per Day

input group "=== ICT MODULES ==="
input int    ICT_Lookback      = 5;                 // Swing Detection Lookback
input bool   ICT_UseLondonKZ   = true;              // Enable London Kill Zone
input bool   ICT_UseNYKZ       = true;              // Enable NY Kill Zone
input bool   ICT_UseHigherTFFilter = true;           // Require Daily Bias Confirmation

input group "=== SIGNAL FILTERING ==="
input int    ICT_MinConfidence = 60;                 // Minimum Signal Confidence (0-100)
input bool   ICT_UseKillZoneOnly = true;             // Only Trade in Kill Zones

input group "=== BACKTESTING ==="
input double ICT_FixedLot      = 0.0;                // Fixed lot (0 = use risk calc)
input bool   ICT_DebugMode    = true;               // Enable debug prints

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS                                                    |
//+------------------------------------------------------------------+
CMarketStructure g_struct;
COrderBlocks    g_ob;
CFairValueGap   g_fvg;
CLiquidityPools g_liq;
CKillZones      g_kz;
CPDArray        g_pd;
CRiskManager    g_rm;
CSignalGenerator g_sig;

//+------------------------------------------------------------------+
//| EXPERT ADVISOR ONINIT                                             |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize all modules
    g_struct.Init(PERIOD_D1, ICT_Symbol, ICT_Lookback);
    g_ob.Init(ICT_Symbol, PERIOD_M5, &g_struct);
    g_fvg.Init(ICT_Symbol, PERIOD_M5);
    g_liq.Init(ICT_Symbol, PERIOD_M5, ICT_Lookback);
    g_kz.Init();
    g_pd.Init(ICT_Symbol, PERIOD_D1);
    g_rm.Init(ICT_Symbol, ICT_RiskPercent, ICT_MaxDailyLoss);
    g_sig.Init(
        ICT_Symbol, &g_struct, &g_ob, &g_fvg,
        &g_liq, &g_kz, &g_pd, &g_rm, PERIOD_M5
    );
    g_sig.SetMinConfidence(ICT_MinConfidence);

    Print("=== ICT EA Initialized ===");
    Print("Symbol: ", ICT_Symbol);
    Print("Risk: ", DoubleToString(ICT_RiskPercent, 2), "% per trade");
    Print("Daily Cap: ", DoubleToString(ICT_MaxDailyLoss, 2), "%");
    Print("Min Confidence: ", ICT_MinConfidence);
    Print("=== Ready to trade ===");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT ADVISOR ONDEINIT                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("=== ICT EA Deinitialized === Reason: ", reason);
}

//+------------------------------------------------------------------+
//| EXPERT ADVISOR ONTICK                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Refresh all modules on every tick
    g_struct.Refresh();
    g_ob.Refresh(20);
    g_fvg.Refresh(30);
    g_liq.Refresh();
    g_kz.Refresh();
    g_pd.Refresh();
    g_rm.Refresh();

    // Debug output
    if(ICT_DebugMode) {
        static datetime lastDebug = 0;
        if(TimeCurrent() - lastDebug >= 60) { // Print every 60 seconds
            PrintDebugStatus();
            lastDebug = TimeCurrent();
        }
    }

    // Check for new signal
    SSignal sig = g_sig.CheckSignals();

    // Execute if signal meets criteria
    if(sig.direction != SIGNAL_NONE && sig.confidence >= ICT_MinConfidence) {
        if(ICT_DebugMode) {
            Print(">>> SIGNAL DETECTED: ", EnumToString(sig.direction),
                  " | Confidence: ", sig.confidence,
                  " | Reason: ", sig.reason);
        }
        ExecuteTrade(sig);
    }
}

//+------------------------------------------------------------------+
//| EXPERT ADVISOR ONCALC                                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const double &spread[]) {
    return rates_total;
}

//+------------------------------------------------------------------+
//| TRADE EXECUTION                                                  |
//+------------------------------------------------------------------+
void ExecuteTrade(SSignal &sig) {
    // Check if we already have a position open
    if(PositionSelect(ICT_Symbol)) {
        if(ICT_DebugMode) Print("Position already open — skipping");
        return;
    }

    // Calculate lot size based on SL distance
    double slPips = MathAbs(sig.entryPrice - sig.stopLoss) /
                    (SymbolInfoDouble(ICT_Symbol, SYMBOL_POINT) * 10);
    double lotSize = g_rm.CalcLotSize(slPips);

    if(lotSize <= 0) {
        if(ICT_DebugMode) Print("Invalid lot size — aborting trade");
        return;
    }

    // Override with fixed lot if specified
    if(ICT_FixedLot > 0) lotSize = ICT_FixedLot;

    MqlTradeRequest request = {};
    MqlTradeResult  result  = {};

    ZeroMemory(request);
    request.action        = TRADE_ACTION_DEAL;
    request.symbol       = ICT_Symbol;
    request.volume       = lotSize;
    request.price        = sig.entryPrice;
    request.sl          = sig.stopLoss;
    request.tp          = sig.takeProfit;
    request.deviation   = 10;
    request.type        = (sig.direction == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.type_filling = ORDER_FILLING_FOK;

    if(!OrderSend(request, result)) {
        Print("OrderSend failed: ", result.comment);
        return;
    }

    if(result.retcode == TRADE_RETCODE_DONE) {
        g_kz.MarkTradeTaken();
        if(ICT_DebugMode) {
            Print(">>> TRADE OPENED: ", EnumToString(sig.direction),
                  " | Lot: ", DoubleToString(lotSize, 2),
                  " | Entry: ", sig.entryPrice,
                  " | SL: ", sig.stopLoss,
                  " | TP: ", sig.takeProfit);
        }
    } else {
        Print("Order rejected: ", result.retcode, " — ", result.comment);
    }
}

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
    // Track when positions close
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal)) {
        long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
        if(entryType == DEAL_ENTRY_OUT) {
            bool isWin = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) > 0.0;
            double entryPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            double exitPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            double stopLoss = HistoryDealGetDouble(trans.deal, DEAL_SL);
            double takeProfit = HistoryDealGetDouble(trans.deal, DEAL_TP);
            double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
            bool isBuy = HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY;

            g_rm.RecordTrade(
                entryPrice, exitPrice,
                stopLoss, takeProfit,
                volume, isWin,
                isBuy
            );
            g_kz.RecordSessionResult(isWin);
        }
    }
}

//+------------------------------------------------------------------+
//| DEBUG STATUS PRINT                                               |
//+------------------------------------------------------------------+
void PrintDebugStatus() {
    double bid = SymbolInfoDouble(ICT_Symbol, SYMBOL_BID);

    ENUM_PD_STATE bias = g_pd.GetDailyBias();
    string biasStr = (bias == PD_BULLISH) ? "BULLISH" :
                     (bias == PD_BEARISH) ? "BEARISH" : "NEUTRAL";

    Print("--- ICT DEBUG ---");
    Print("Bias: ", biasStr, " | Price: ", bid);
    Print("KillZone: ", g_kz.IsKillZoneActive() ? "ACTIVE" : "inactive");
    Print("Structure: ", EnumToString(g_struct.GetState()));
    Print("Equity: ", DoubleToString(g_rm.GetEquity(), 2),
          " | Daily P&L: ", DoubleToString(g_rm.GetDailyPnL(), 2));
    Print("Active Bull OBs: ", g_ob.CountActiveBullishOBs(),
          " | Active Bear OBs: ", g_ob.CountActiveBearishOBs());
}

//+------------------------------------------------------------------+
//| END: ICT_EA.mq5                                                   |
//+------------------------------------------------------------------+