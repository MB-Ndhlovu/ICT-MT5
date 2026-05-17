//+------------------------------------------------------------------+
//|  ICT Risk Manager Module                                          |
//|  File: ICT_RiskManager.mqh                                        |
//|  Author: Malibongwe Ndhlovu                                       |
//|  Supervisor: Ben JARVIS AI                                        |
//|  Date: 2026-05-17                                                 |
//+------------------------------------------------------------------+

#ifndef ICT_RISK_MANAGER_MQH
#define ICT_RISK_MANAGER_MQH

//+------------------------------------------------------------------+
//| ENUM: Risk State                                                  |
//+------------------------------------------------------------------+
enum ENUM_RISK_STATE {
    RISK_OK,           // Normal operation
    RISK_WARNING,      // Approaching daily limit
    RISK_HALTED,       // Daily loss cap hit — trading halted
    RISK_DAILY_RESET   // New trading day — reset counters
};

//+------------------------------------------------------------------+
//| STRUCT: Trade Record                                              |
//+------------------------------------------------------------------+
struct STradeRecord {
    double    entryPrice;
    double    exitPrice;
    double    stopLoss;
    double    takeProfit;
    double    lotSize;
    double    riskAmount;
    double    pnl;
    bool      isWin;
    bool      isBuy;
    datetime  openTime;
    datetime  closeTime;
    string    symbol;
};

//+------------------------------------------------------------------+
//| CLASS: CRiskManager                                               |
//+------------------------------------------------------------------+
class CRiskManager {
private:
    string        m_symbol;
    double        m_riskPercent;       // Risk per trade (%)
    double        m_maxDailyLoss;     // Max daily loss (%)
    double        m_dailyLossCap;      // Calculated from equity
    double        m_accountEquity;
    double        m_dailyPnL;         // Running P&L for the day
    double        m_sessionPnL;       // Session P&L
    int           m_consecutiveLosses;
    int           m_maxConsecutiveLosses;
    datetime      m_lastResetDate;
    STradeRecord  m_tradeHistory[];
    ENUM_RISK_STATE m_state;

    // Pip value per symbol (must be calibrated)
    double m_pipValue;

    // Calculate pip value for symbol
    double GetPipValue(string symbol) {
        // XAUUSD: 1 pip = $0.10 for 0.01 lot on $2000 gold
        // NAS100/US30: 1 pip = $0.10 for 0.01 lot
        if(StringFind(symbol, "XAU") >= 0)    return 10.0;    // Per lot per pip
        if(StringFind(symbol, "NAS") >= 0)    return 10.0;
        if(StringFind(symbol, "US") >= 0)     return 10.0;
        return 10.0; // Default
    }

    // Normalize stop loss to pips
    int NormalizeToPips(double slDistance, string symbol) {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        double pipSize = (digits == 3 || digits == 5) ? point * 10 : point;
        return (int)(slDistance / pipSize);
    }

    // Calculate lot size
    double CalculateLotSize(string symbol, double stopLossPips) {
        if(stopLossPips <= 0) return 0;
        double riskAmount = m_accountEquity * (m_riskPercent / 100.0);
        double pipValue = GetPipValue(symbol);
        double lotSize = riskAmount / (stopLossPips * pipValue);
        // Normalize to broker lot step
        double minLot   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double lotStep  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        lotSize = MathMax(minLot, MathRound(lotSize / lotStep) * lotStep);
        // Max lot check
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        return MathMin(lotSize, maxLot);
    }

public:
    CRiskManager() {
        m_riskPercent      = 1.0;
        m_maxDailyLoss    = 2.0;
        m_dailyPnL         = 0;
        m_sessionPnL       = 0;
        m_consecutiveLosses = 0;
        m_maxConsecutiveLosses = 5;
        m_state           = RISK_OK;
        m_lastResetDate   = 0;
        ArrayResize(m_tradeHistory, 0);
    }

    void Init(string symbol, double riskPercent = 1.0, double maxDailyLoss = 2.0) {
        m_symbol        = symbol;
        m_riskPercent   = riskPercent;
        m_maxDailyLoss = maxDailyLoss;
        m_pipValue      = GetPipValue(symbol);
        m_accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_dailyLossCap  = m_accountEquity * (m_maxDailyLoss / 100.0);
        CheckDailyReset();
    }

    // Call on every tick to update equity and check limits
    void Refresh() {
        m_accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_dailyLossCap  = m_accountEquity * (m_maxDailyLoss / 100.0);
        CheckDailyReset();

        if(m_state == RISK_HALTED) return;

        if(m_dailyPnL <= -m_dailyLossCap)
            m_state = RISK_HALTED;
        else if(m_dailyPnL <= -m_dailyLossCap * 0.5)
            m_state = RISK_WARNING;
    }

    // Check if it's a new trading day — reset counters
    void CheckDailyReset() {
        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);
        datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));

        if(m_lastResetDate < todayStart) {
            m_lastResetDate   = todayStart;
            m_dailyPnL         = 0;
            m_sessionPnL      = 0;
            m_consecutiveLosses = 0;
            m_state           = RISK_OK;
        }
    }

    // Pre-trade risk check — call before opening any position
    bool CanOpenTrade() {
        Refresh();
        if(m_state == RISK_HALTED) return false;
        if(m_consecutiveLosses >= m_maxConsecutiveLosses) return false;
        return true;
    }

    // Calculate lot size for a given stop loss distance
    double CalcLotSize(double stopLossPips) {
        return CalculateLotSize(m_symbol, stopLossPips);
    }

    // Calculate stop loss in price units from pips
    double CalcStopLoss(double entryPrice, int stopLossPips, bool isBuy) {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        double pipSize = (digits == 3 || digits == 5) ? point * 10 : point;
        double slDistance = stopLossPips * pipSize;
        return isBuy ? entryPrice - slDistance : entryPrice + slDistance;
    }

    // Calculate take profit (1:3 RR by default, configurable)
    double CalcTakeProfit(double entryPrice, int stopLossPips, bool isBuy, double rrRatio = 3.0) {
        double tpDistance = stopLossPips * rrRatio;
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        double pipSize = (digits == 3 || digits == 5) ? point * 10 : point;
        double tpPips = tpDistance * pipSize;
        return isBuy ? entryPrice + tpPips : entryPrice - tpPips;
    }

    // Record a closed trade
    void RecordTrade(double entry, double exit, double sl, double tp, double lots, bool isWin, bool isBuy) {
        STradeRecord t;
        t.entryPrice  = entry;
        t.exitPrice   = exit;
        t.stopLoss    = sl;
        t.takeProfit  = tp;
        t.lotSize     = lots;
        t.isWin       = isWin;
        t.isBuy       = isBuy;
        t.openTime    = TimeCurrent();
        t.closeTime   = TimeCurrent();
        t.symbol      = m_symbol;

        double riskAmount = lots * MathAbs(sl - entry) * m_pipValue;
        t.riskAmount = riskAmount;
        t.pnl = isWin ? riskAmount * 3.0 : -riskAmount;

        int size = ArraySize(m_tradeHistory);
        ArrayResize(m_tradeHistory, size + 1);
        m_tradeHistory[size] = t;

        m_dailyPnL += t.pnl;
        m_sessionPnL += t.pnl;

        if(isWin)
            m_consecutiveLosses = 0;
        else
            m_consecutiveLosses++;
    }

    // Get current state
    ENUM_RISK_STATE GetState() {
        return m_state;
    }

    // Get daily P&L
    double GetDailyPnL() {
        return m_dailyPnL;
    }

    // Get current equity
    double GetEquity() {
        return m_accountEquity;
    }

    // Get risk percent
    double GetRiskPercent() {
        return m_riskPercent;
    }

    // Force daily reset (for new day)
    void ForceDailyReset() {
        m_lastResetDate = TimeCurrent();
        m_dailyPnL = 0;
        m_sessionPnL = 0;
        m_consecutiveLosses = 0;
        m_state = RISK_OK;
    }

    // Get trade history summary
    int GetTradeCount() {
        return ArraySize(m_tradeHistory);
    }

    double GetTodayWinRate() {
        int total = ArraySize(m_tradeHistory);
        if(total == 0) return 0;
        int wins = 0;
        for(int i = 0; i < total; i++)
            if(m_tradeHistory[i].isWin) wins++;
        return (double)wins / total;
    }
};

#endif // ICT_RISK_MANAGER_MQH
//+------------------------------------------------------------------+
//| END: ICT_RISK_MANAGER_MQH                                         |
//+------------------------------------------------------------------+