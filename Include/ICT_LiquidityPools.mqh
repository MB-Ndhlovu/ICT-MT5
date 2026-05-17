//+------------------------------------------------------------------+
//|  ICT Liquidity Pools Module                                       |
//|  File: ICT_LiquidityPools.mqh                                     |
//|  Author: Malibongwe Ndhlovu                                       |
//|  Supervisor: Ben JARVIS AI                                        |
//|  Date: 2026-05-17                                                 |
//+------------------------------------------------------------------+

#ifndef ICT_LIQUIDITY_POOLS_MQH
#define ICT_LIQUIDITY_POOLS_MQH

//+------------------------------------------------------------------+
//| ENUM: Liquidity Type                                              |
//+------------------------------------------------------------------+
enum ENUM_LIQ_TYPE {
    LIQ_BSL,   // Buy-Side Liquidity — swing highs (institutional sell stops)
    LIQ_SSL,   // Sell-Side Liquidity — swing lows (institutional buy stops)
    LIQ_EQH,   // Equal Highs — same level liquidity
    LIQ_EQL    // Equal Lows — same level liquidity
};

//+------------------------------------------------------------------+
//| ENUM: Sweep State                                                 |
//+------------------------------------------------------------------+
enum ENUM_SWEEP_STATE {
    SWEEP_NONE,       // No sweep detected
    SWEEP_DETECTED,   // Sweep confirmed, reversal likely
    SWEEP_CONFIRMED   // Price returned and confirmed entry
};

//+------------------------------------------------------------------+
//| STRUCT: Liquidity Pool                                            |
//+------------------------------------------------------------------+
struct SLiquidityPool {
    double         price;        // Level of the liquidity pool
    ENUM_LIQ_TYPE  type;         // BSL, SSL, EQH, EQL
    int            strength;     // 1-10 strength rating
    int            barIndex;     // When it was formed
    datetime       time;
    int            touches;       // How many times price approached
    bool           isSwept;       // Whether pool has been swept
    double         sweepVolume;  // Volume at the sweep
    ENUM_SWEEP_STATE state;
};

//+------------------------------------------------------------------+
//| CLASS: CLiquidityPools                                            |
//+------------------------------------------------------------------+
class CLiquidityPools {
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int             m_maxPools;
    SLiquidityPool  m_pools[];
    int             m_lookback;

    // Find swing highs/lows using pivot method
    bool IsSwingHigh(int index, int lookback) {
        if(index < lookback || index >= iBars(m_symbol, m_timeframe) - lookback)
            return false;

        double high = iHigh(m_symbol, m_timeframe, index);
        for(int i = 1; i <= lookback; i++) {
            if(iHigh(m_symbol, m_timeframe, index - i) >= high) return false;
            if(iHigh(m_symbol, m_timeframe, index + i) >= high) return false;
        }
        return true;
    }

    bool IsSwingLow(int index, int lookback) {
        if(index < lookback || index >= iBars(m_symbol, m_timeframe) - lookback)
            return false;

        double low = iLow(m_symbol, m_timeframe, index);
        for(int i = 1; i <= lookback; i++) {
            if(iLow(m_symbol, m_timeframe, index - i) <= low) return false;
            if(iLow(m_symbol, m_timeframe, index + i) <= low) return false;
        }
        return true;
    }

    // Detect equal highs / equal lows within tolerance
    bool IsEqualHigh(int index, int lookback) {
        if(index < lookback) return false;
        double high1 = iHigh(m_symbol, m_timeframe, index);
        double tolerance = high1 * _Point * 10; // 10 pip tolerance

        for(int i = index - 1; i >= index - lookback && i >= 0; i--) {
            double high2 = iHigh(m_symbol, m_timeframe, i);
            if(MathAbs(high1 - high2) <= tolerance)
                return true;
        }
        return false;
    }

    bool IsEqualLow(int index, int lookback) {
        if(index < lookback) return false;
        double low1 = iLow(m_symbol, m_timeframe, index);
        double tolerance = low1 * _Point * 10;

        for(int i = index - 1; i >= index - lookback && i >= 0; i--) {
            double low2 = iLow(m_symbol, m_timeframe, i);
            if(MathAbs(low1 - low2) <= tolerance)
                return true;
        }
        return false;
    }

    // Detect liquidity sweep — price spikes beyond a pool then reverses
    ENUM_SWEEP_STATE DetectSweep(double price, double high, double low) {
        // Sweep condition: price goes beyond key level (high/low) then reverses
        double range = high - low;
        double threshold = range * 0.001; // 0.1% spike threshold

        if(price > high + threshold && price < high + range * 0.005)
            return SWEEP_DETECTED; // Swept BSL
        if(price < low - threshold && price > low - range * 0.005)
            return SWEEP_DETECTED; // Swept SSL

        return SWEEP_NONE;
    }

public:
    CLiquidityPools() {
        m_maxPools  = 20;
        m_lookback  = 5;
    }

    void Init(string symbol, ENUM_TIMEFRAMES timeframe, int lookback = 5) {
        m_symbol    = symbol;
        m_timeframe = timeframe;
        m_lookback  = lookback;
        ArrayResize(m_pools, 0);
    }

    void Refresh() {
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        int totalBars = iBars(m_symbol, m_timeframe);

        // Scan for BSL (swing highs) and SSL (swing lows)
        for(int i = m_lookback; i >= 2 && i < totalBars - m_lookback; i--) {
            // Check for new swing high = potential BSL
            if(IsSwingHigh(i, m_lookback)) {
                double price = iHigh(m_symbol, m_timeframe, i);
                // Check if this is also an equal high
                ENUM_LIQ_TYPE ltype = IsEqualHigh(i, m_lookback * 2) ? LIQ_EQH : LIQ_BSL;

                SLiquidityPool pool;
                pool.price   = price;
                pool.type    = ltype;
                pool.barIndex = i;
                pool.time    = iTime(m_symbol, m_timeframe, i);
                pool.strength = 5;
                pool.touches = 1;
                pool.isSwept = false;
                pool.state   = SWEEP_NONE;

                // Check if pool already exists at this level
                bool exists = false;
                for(int j = 0; j < ArraySize(m_pools); j++) {
                    if(MathAbs(m_pools[j].price - price) < price * _Point * 20) {
                        m_pools[j].touches++;
                        m_pools[j].strength = MathMin(10, m_pools[j].strength + 1);
                        exists = true;
                        break;
                    }
                }

                if(!exists) {
                    int size = ArraySize(m_pools);
                    ArrayResize(m_pools, size + 1);
                    m_pools[size] = pool;
                }
            }

            // Check for new swing low = potential SSL
            if(IsSwingLow(i, m_lookback)) {
                double price = iLow(m_symbol, m_timeframe, i);
                ENUM_LIQ_TYPE ltype = IsEqualLow(i, m_lookback * 2) ? LIQ_EQL : LIQ_SSL;

                SLiquidityPool pool;
                pool.price   = price;
                pool.type    = ltype;
                pool.barIndex = i;
                pool.time    = iTime(m_symbol, m_timeframe, i);
                pool.strength = 5;
                pool.touches = 1;
                pool.isSwept = false;
                pool.state   = SWEEP_NONE;

                bool exists = false;
                for(int j = 0; j < ArraySize(m_pools); j++) {
                    if(MathAbs(m_pools[j].price - price) < price * _Point * 20) {
                        m_pools[j].touches++;
                        m_pools[j].strength = MathMin(10, m_pools[j].strength + 1);
                        exists = true;
                        break;
                    }
                }

                if(!exists) {
                    int size = ArraySize(m_pools);
                    ArrayResize(m_pools, size + 1);
                    m_pools[size] = pool;
                }
            }
        }

        // Update sweep detection
        double high = iHigh(m_symbol, m_timeframe, 1);
        double low  = iLow(m_symbol, m_timeframe, 1);
        for(int i = 0; i < ArraySize(m_pools); i++) {
            if(m_pools[i].isSwept) continue;

            ENUM_SWEEP_STATE sweep = DetectSweep(bid, m_pools[i].price, m_pools[i].price);
            if(sweep == SWEEP_DETECTED) {
                // Check for reversal confirmation
                double closePrice = iClose(m_symbol, m_timeframe, 1);
                if(m_pools[i].type == LIQ_BSL || m_pools[i].type == LIQ_EQH) {
                    if(closePrice < m_pools[i].price)
                        m_pools[i].state = SWEEP_CONFIRMED;
                } else {
                    if(closePrice > m_pools[i].price)
                        m_pools[i].state = SWEEP_CONFIRMED;
                }
                m_pools[i].isSwept = true;
            }
        }

        // Trim to max pools
        while(ArraySize(m_pools) > m_maxPools) {
            for(int i = 0; i < ArraySize(m_pools) - 1; i++)
                m_pools[i] = m_pools[i + 1];
            ArrayResize(m_pools, ArraySize(m_pools) - 1);
        }
    }

    // Get nearest unswept BSL above price
    bool GetNearestBSL(double price, SLiquidityPool &pool) {
        double minDist = DBL_MAX;
        bool found = false;

        for(int i = 0; i < ArraySize(m_pools); i++) {
            if(m_pools[i].type != LIQ_BSL && m_pools[i].type != LIQ_EQH) continue;
            if(m_pools[i].isSwept) continue;
            if(m_pools[i].price < price) continue; // Must be above

            double dist = m_pools[i].price - price;
            if(dist < minDist) {
                minDist = dist;
                pool = m_pools[i];
                found = true;
            }
        }
        return found;
    }

    // Get nearest unswept SSL below price
    bool GetNearestSSL(double price, SLiquidityPool &pool) {
        double minDist = DBL_MAX;
        bool found = false;

        for(int i = 0; i < ArraySize(m_pools); i++) {
            if(m_pools[i].type != LIQ_SSL && m_pools[i].type != LIQ_EQL) continue;
            if(m_pools[i].isSwept) continue;
            if(m_pools[i].price > price) continue; // Must be below

            double dist = price - m_pools[i].price;
            if(dist < minDist) {
                minDist = dist;
                pool = m_pools[i];
                found = true;
            }
        }
        return found;
    }

    // Was the last move a liquidity sweep? (returns sweep type or NONE)
    ENUM_SWEEP_STATE WasLiquiditySwept() {
        for(int i = 0; i < ArraySize(m_pools); i++) {
            if(m_pools[i].state == SWEEP_CONFIRMED)
                return SWEEP_CONFIRMED;
        }
        return SWEEP_NONE;
    }

    // Get total pool strength at a price level (for confluence scoring)
    int GetPoolStrength(double price, bool isBullishSetup) {
        int strength = 0;
        for(int i = 0; i < ArraySize(m_pools); i++) {
            double dist = MathAbs(price - m_pools[i].price);
            if(dist < price * _Point * 50) { // Within 50 pips
                if(isBullishSetup && (m_pools[i].type == LIQ_SSL || m_pools[i].type == LIQ_EQL))
                    strength += m_pools[i].strength;
                else if(!isBullishSetup && (m_pools[i].type == LIQ_BSL || m_pools[i].type == LIQ_EQH))
                    strength += m_pools[i].strength;
            }
        }
        return MathMin(strength, 30); // Cap at 30 for scoring
    }
};

#endif // ICT_LIQUIDITY_POOLS_MQH
//+------------------------------------------------------------------+
//| END: ICT_LiquidityPools.mqh                                      |
//+------------------------------------------------------------------+