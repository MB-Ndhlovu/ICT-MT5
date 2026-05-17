//+------------------------------------------------------------------+
//|  ICT PD Array Module                                              |
//|  File: ICT_PDArray.mqh                                            |
//|  Author: Malibongwe Ndhlovu                                       |
//|  Supervisor: Ben JARVIS AI                                        |
//|  Date: 2026-05-17                                                 |
//+------------------------------------------------------------------+

#ifndef ICT_PD_ARRAY_MQH
#define ICT_PD_ARRAY_MQH

#include <ICT_MarketStructure.mqh>

//+------------------------------------------------------------------+
//| ENUM: Zone Type                                                   |
//+------------------------------------------------------------------+
enum ENUM_ZONE_TYPE {
    ZONE_PREMIUM,     // Above 50% Fib — bearish bias area
    ZONE_DISCOUNT,    // Below 50% Fib — bullish bias area
    ZONE_MIDDLE,      // Between 38.2% and 61.8% — no trade zone
    ZONE_OTE_BUY,     // 62-79% retrace — optimal buy entry
    ZONE_OTE_SELL,    // 62-79% retrace — optimal sell entry
    ZONE_EQWL         // Equal Wave Low — measured move target
};

//+------------------------------------------------------------------+
//| ENUM: PD Array State                                              |
//+------------------------------------------------------------------+
enum ENUM_PD_STATE {
    PD_BULLISH,   // Bias bullish — look for buys
    PD_BEARISH,   // Bias bearish — look for sells
    PD_NEUTRAL    // No clear bias
};

//+------------------------------------------------------------------+
//| STRUCT: PD Array Zone                                             |
//+------------------------------------------------------------------+
struct SPDArrayZone {
    double          price;       // Price level of this zone
    double          level;        // Alias for the same price level
    string          label;       // Human-readable Fib label
    ENUM_ZONE_TYPE  type;        // Zone classification
    double          fibRetrace;  // 0.382, 0.500, 0.618, etc.
    bool            isActive;    // Is price currently in this zone?
    double          confluence;  // 0-100 confluence score
    int             toolsCount;  // How many ICT tools agree here
};

//+------------------------------------------------------------------+
//| STRUCT: Fib Levels                                                |
//+------------------------------------------------------------------+
struct SFibLevel {
    double price;
    double retrace;   // 0.0 to 1.0
    string label;
    bool   isKey;     // Is this a key level (38.2, 50, 61.8, 78.6)?
};

//+------------------------------------------------------------------+
//| CLASS: CPDArray                                                   |
//+------------------------------------------------------------------+
class CPDArray {
private:
    string          m_symbol;
    ENUM_TIMEFRAMES  m_dailyTf;
    int             m_lookback;         // Days to look back for range
    SPDArrayZone    m_zones[];           // Detected zones
    SFibLevel       m_fibLevels[];       // 8 standard Fib levels
    ENUM_PD_STATE   m_dailyBias;         // Today's bias
    double          m_dailyHigh;
    double          m_dailyLow;
    double          m_dailyRange;
    double          m_fib50;             // 50% level
    double          m_oteZoneBuy;        // OTE buy zone (62-79%)
    double          m_oteZoneSell;       // OTE sell zone (62-79%)

    // Calculate daily range and Fib levels
    void CalculateDailyFib() {
        m_dailyHigh = iHigh(m_symbol, m_dailyTf, 1);
        m_dailyLow  = iLow(m_symbol, m_dailyTf, 1);
        m_dailyRange = m_dailyHigh - m_dailyLow;

        m_fib50 = m_dailyLow + m_dailyRange * 0.500;

        // OTE zones (62-79% retracement)
        m_oteZoneBuy  = m_dailyHigh - m_dailyRange * 0.786;  // Strongest buy
        m_oteZoneSell = m_dailyLow  + m_dailyRange * 0.786;  // Strongest sell

        // Build Fib levels array
        ArrayResize(m_fibLevels, 8);
        double fibs[] = {0.000, 0.236, 0.382, 0.500, 0.618, 0.786, 1.000, 1.618};
        string labels[] = {"0%", "23.6%", "38.2%", "50%", "61.8%", "78.6%", "100%", "161.8%"};
        bool keys[]    = {false, false, true, true, true, true, false, true};

        for(int i = 0; i < 8; i++) {
            m_fibLevels[i].price    = m_dailyLow + m_dailyRange * fibs[i];
            m_fibLevels[i].retrace  = fibs[i];
            m_fibLevels[i].label    = labels[i];
            m_fibLevels[i].isKey    = keys[i];
        }
    }

    // Determine daily bias from price position
    ENUM_PD_STATE DetermineBias(double bid) {
        if(bid > m_fib50)
            return PD_BEARISH;  // Above 50% = sell side
        else if(bid < m_fib50)
            return PD_BULLISH; // Below 50% = buy side
        else
            return PD_NEUTRAL;
    }

    // Calculate confluence score for a price level
    int CalculateConfluence(double price) {
        int score = 0;

        // Check distance to key Fib levels
        for(int i = 0; i < ArraySize(m_fibLevels); i++) {
            if(!m_fibLevels[i].isKey) continue;
            double dist = MathAbs(price - m_fibLevels[i].price);
            double range = m_dailyRange * 0.01; // 1% of daily range as tolerance
            if(dist < range) score += 10;
            else if(dist < range * 3) score += 5;
        }

        return MathMin(score, 100);
    }

public:
    CPDArray() {
        m_dailyTf   = PERIOD_D1;
        m_lookback  = 20;
        m_dailyBias = PD_NEUTRAL;
    }

    void Init(string symbol, ENUM_TIMEFRAMES dailyTf = PERIOD_D1) {
        m_symbol   = symbol;
        m_dailyTf  = dailyTf;
        ArrayResize(m_zones, 0);
    }

    void Refresh() {
        CalculateDailyFib();
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        m_dailyBias = DetermineBias(bid);

        // Build zone array
        ArrayResize(m_zones, 0);
        int size = 0;

        for(int i = 0; i < ArraySize(m_fibLevels); i++) {
            if(!m_fibLevels[i].isKey) continue;

            SPDArrayZone z;
            z.price      = m_fibLevels[i].price;
            z.level      = m_fibLevels[i].price;
            z.label      = m_fibLevels[i].label;
            z.fibRetrace = m_fibLevels[i].retrace;
            z.confluence = CalculateConfluence(m_fibLevels[i].price);
            z.toolsCount = 0;

            if(m_fibLevels[i].retrace >= 0.382 && m_fibLevels[i].retrace <= 0.500)
                z.type = ZONE_DISCOUNT;
            else if(m_fibLevels[i].retrace >= 0.618 && m_fibLevels[i].retrace <= 1.000)
                z.type = ZONE_PREMIUM;
            else if(m_fibLevels[i].retrace >= 0.618 && m_fibLevels[i].retrace <= 0.786)
                z.type = ZONE_OTE_BUY;
            else
                z.type = ZONE_MIDDLE;

            ArrayResize(m_zones, size + 1);
            m_zones[size++] = z;
        }

        // Mark active zones based on current price
        for(int i = 0; i < ArraySize(m_zones); i++) {
            double dist = MathAbs(bid - m_zones[i].price);
            m_zones[i].isActive = (dist < m_dailyRange * 0.005); // Within 0.5% of level
        }
    }

    // Get daily bias
    ENUM_PD_STATE GetDailyBias() {
        return m_dailyBias;
    }

    // Is price in discount zone? (buy side)
    bool IsInDiscountZone(double price) {
        return price < m_fib50;
    }

    // Is price in premium zone? (sell side)
    bool IsInPremiumZone(double price) {
        return price > m_fib50;
    }

    // Is price in OTE buy zone?
    bool IsInOTEBuyZone(double price) {
        double oteLow  = m_dailyHigh - m_dailyRange * 0.790;
        double oteHigh = m_dailyHigh - m_dailyRange * 0.618;
        return price >= oteLow && price <= oteHigh;
    }

    // Is price in OTE sell zone?
    bool IsInOTESellZone(double price) {
        double oteLow  = m_dailyLow + m_dailyRange * 0.618;
        double oteHigh = m_dailyLow + m_dailyRange * 0.790;
        return price >= oteLow && price <= oteHigh;
    }

    // Get nearest Fib level to current price
    bool GetNearestFibLevel(double price, SFibLevel &level) {
        double minDist = DBL_MAX;
        bool found = false;

        for(int i = 0; i < ArraySize(m_fibLevels); i++) {
            double dist = MathAbs(price - m_fibLevels[i].price);
            if(dist < minDist) {
                minDist = dist;
                level = m_fibLevels[i];
                found = true;
            }
        }
        return found;
    }

    // Get the OTE buy zone price range
    void GetOTEBuyZone(double &lower, double &upper) {
        lower = m_dailyHigh - m_dailyRange * 0.790;
        upper = m_dailyHigh - m_dailyRange * 0.618;
    }

    // Get the OTE sell zone price range
    void GetOTESellZone(double &lower, double &upper) {
        lower = m_dailyLow + m_dailyRange * 0.618;
        upper = m_dailyLow + m_dailyRange * 0.790;
    }

    // Get 50% level
    double GetFib50() {
        return m_fib50;
    }

    // Get daily high
    double GetDailyHigh() {
        return m_dailyHigh;
    }

    // Get daily low
    double GetDailyLow() {
        return m_dailyLow;
    }
};

#endif // ICT_PD_ARRAY_MQH
//+------------------------------------------------------------------+
//| END: ICT_PDArray.mqh                                              |
//+------------------------------------------------------------------+