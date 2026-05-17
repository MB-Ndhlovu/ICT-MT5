//+------------------------------------------------------------------+
//|  ICT Fair Value Gap Module                                        |
//|  File: ICT_FairValueGap.mqh                                       |
//|  Author: Malibongwe Ndhlovu                                       |
//|  Supervisor: Ben JARVIS AI                                        |
//|  Date: 2026-05-17                                                 |
//+------------------------------------------------------------------+

#ifndef ICT_FAIR_VALUE_GAP_MQH
#define ICT_FAIR_VALUE_GAP_MQH

//+------------------------------------------------------------------+
//| ENUM: FVG Type                                                    |
//+------------------------------------------------------------------+
enum ENUM_FVG_TYPE {
    FVG_BULL,   // Bullish FVG — upward gap (buy)
    FVG_BEAR,   // Bearish FVG — downward gap (sell)
    FVG_NONE    // No FVG
};

//+------------------------------------------------------------------+
//| ENUM: FVG State                                                   |
//+------------------------------------------------------------------+
enum ENUM_FVG_STATE {
    FVG_OPEN,      // Gap not yet filled — highest probability
    FVG_PARTIAL,   // Price partially filled the gap
    FVG_FILLED,    // Gap fully filled — no longer valid
    FVG_WIDENING   // Gap growing — strong momentum continuation
};

//+------------------------------------------------------------------+
//| STRUCT: Fair Value Gap                                            |
//+------------------------------------------------------------------+
struct SFairValueGap {
    double  upper;       // Top boundary of the gap
    double  lower;       // Bottom boundary of the gap
    int     index;       // Bar index of the middle candle (gap center)
    ENUM_FVG_TYPE type; // Bullish or Bearish
    ENUM_FVG_STATE state;
    double  fillRatio;   // 0 = unfilled, 1 = fully filled
    datetime time;       // Formation time
    double  size;        // Gap size in points
};

//+------------------------------------------------------------------+
//| CLASS: CFairValueGap                                              |
//+------------------------------------------------------------------+
class CFairValueGap {
private:
    string        m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int           m_maxFVGs;
    SFairValueGap m_bullFVGs[];
    SFairValueGap m_bearFVGs[];

    // Detect a bullish FVG at index (the middle candle of the 3-candle pattern)
    // Pattern: candle[i+1] is bullish, candle[i+1] high > candle[i-1] low (gap up)
    bool DetectBullishFVG(int midIndex) {
        // Need at least 3 bars: i-1 (bearish), i (bullish mid), i+1 (bullish continuation)
        if(midIndex < 2 || midIndex >= iBars(m_symbol, m_timeframe) - 1)
            return false;

        double prevLow  = iLow(m_symbol, m_timeframe, midIndex + 1);
        double prevHigh = iHigh(m_symbol, m_timeframe, midIndex + 1);
        double nextHigh = iHigh(m_symbol, m_timeframe, midIndex - 1);
        double nextLow  = iLow(m_symbol, m_timeframe, midIndex - 1);

        // Bullish FVG: next candle's low is ABOVE previous candle's high (gap up)
        if(nextLow <= prevHigh) return false; // No gap

        SFairValueGap fvg;
        fvg.upper = prevHigh;            // Top = upper wick of previous candle
        fvg.lower = nextLow;             // Bottom = low of current candle
        fvg.index = midIndex;
        fvg.type  = FVG_BULL;
        fvg.state = FVG_OPEN;
        fvg.fillRatio = 0.0;
        fvg.time  = iTime(m_symbol, m_timeframe, midIndex);
        fvg.size  = nextLow - prevHigh;  // Gap size in points

        // Only record meaningful gaps (>= 2 pips for XAUUSD, >= 1 pip for forex)
        double minGapSize = (StringFind(m_symbol, "XAU") >= 0) ? 200 * Point() : 100 * Point();
        if(fvg.size < minGapSize) return false;

        int size = ArraySize(m_bullFVGs);
        ArrayResize(m_bullFVGs, size + 1);
        m_bullFVGs[size] = fvg;

        if(ArraySize(m_bullFVGs) > m_maxFVGs)
            ArrayResize(m_bullFVGs, m_maxFVGs);

        return true;
    }

    // Detect a bearish FVG
    bool DetectBearishFVG(int midIndex) {
        if(midIndex < 2 || midIndex >= iBars(m_symbol, m_timeframe) - 1)
            return false;

        double prevLow  = iLow(m_symbol, m_timeframe, midIndex + 1);
        double prevHigh = iHigh(m_symbol, m_timeframe, midIndex + 1);
        double nextHigh = iHigh(m_symbol, m_timeframe, midIndex - 1);
        double nextLow  = iLow(m_symbol, m_timeframe, midIndex - 1);

        // Bearish FVG: next candle's high is BELOW previous candle's low (gap down)
        if(nextHigh >= prevLow) return false;

        SFairValueGap fvg;
        fvg.upper = nextHigh;
        fvg.lower = prevLow;
        fvg.index = midIndex;
        fvg.type  = FVG_BEAR;
        fvg.state = FVG_OPEN;
        fvg.fillRatio = 0.0;
        fvg.time  = iTime(m_symbol, m_timeframe, midIndex);
        fvg.size  = prevLow - nextHigh;

        double minGapSize = (StringFind(m_symbol, "XAU") >= 0) ? 200 * Point() : 100 * Point();
        if(fvg.size < minGapSize) return false;

        int size = ArraySize(m_bearFVGs);
        ArrayResize(m_bearFVGs, size + 1);
        m_bearFVGs[size] = fvg;

        if(ArraySize(m_bearFVGs) > m_maxFVGs)
            ArrayResize(m_bearFVGs, m_maxFVGs);

        return true;
    }

    // Update fill ratio based on current price
    void UpdateFVGStates(double bid, double ask) {
        for(int i = 0; i < ArraySize(m_bullFVGs); i++) {
            if(m_bullFVGs[i].state == FVG_FILLED || m_bullFVGs[i].state == FVG_WIDENING)
                continue;

            // Check if price is filling the gap
            double fillStart = m_bullFVGs[i].upper; // Gap top (where price came from)
            double fillEnd   = m_bullFVGs[i].lower; // Gap bottom (where price went to)

            if(bid <= fillEnd) {
                // Fully filled
                m_bullFVGs[i].state     = FVG_FILLED;
                m_bullFVGs[i].fillRatio = 1.0;
            } else if(bid < fillStart && bid > fillEnd) {
                // Partially filled
                m_bullFVGs[i].state     = FVG_PARTIAL;
                m_bullFVGs[i].fillRatio = (fillStart - bid) / m_bullFVGs[i].size;
            }
            // If bid > upper = widening (gap growing)
            else if(bid > fillStart)
                m_bullFVGs[i].state = FVG_WIDENING;
        }

        for(int i = 0; i < ArraySize(m_bearFVGs); i++) {
            if(m_bearFVGs[i].state == FVG_FILLED || m_bearFVGs[i].state == FVG_WIDENING)
                continue;

            double fillStart = m_bearFVGs[i].lower; // Gap bottom
            double fillEnd   = m_bearFVGs[i].upper; // Gap top

            if(ask >= fillEnd) {
                m_bearFVGs[i].state     = FVG_FILLED;
                m_bearFVGs[i].fillRatio = 1.0;
            } else if(ask > fillStart && ask < fillEnd) {
                m_bearFVGs[i].state     = FVG_PARTIAL;
                m_bearFVGs[i].fillRatio = (ask - fillStart) / m_bearFVGs[i].size;
            } else if(ask < fillStart)
                m_bearFVGs[i].state = FVG_WIDENING;
        }
    }

public:
    CFairValueGap() {
        m_maxFVGs = 15;
    }

    void Init(string symbol, ENUM_TIMEFRAMES timeframe) {
        m_symbol    = symbol;
        m_timeframe = timeframe;
        ArrayResize(m_bullFVGs, 0);
        ArrayResize(m_bearFVGs, 0);
    }

    void Refresh(int lookback = 30) {
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

        for(int i = 1; i <= lookback && i < iBars(m_symbol, m_timeframe) - 1; i++) {
            // The gap center is at bar i — check for FVGs around this bar
            DetectBullishFVG(i);
            DetectBearishFVG(i);
        }

        UpdateFVGStates(bid, ask);
    }

    // Get nearest open bullish FVG below current price
    bool GetNearestOpenBullishFVG(double price, SFairValueGap &fvg) {
        double minDist = DBL_MAX;
        bool found = false;

        for(int i = 0; i < ArraySize(m_bullFVGs); i++) {
            if(m_bullFVGs[i].state == FVG_FILLED) continue;
            // Bullish FVG should be below price for buy setup
            if(m_bullFVGs[i].upper >= price) continue;

            double dist = price - m_bullFVGs[i].upper;
            if(dist < minDist) {
                minDist = dist;
                fvg = m_bullFVGs[i];
                found = true;
            }
        }
        return found;
    }

    // Get nearest open bearish FVG above current price
    bool GetNearestOpenBearishFVG(double price, SFairValueGap &fvg) {
        double minDist = DBL_MAX;
        bool found = false;

        for(int i = 0; i < ArraySize(m_bearFVGs); i++) {
            if(m_bearFVGs[i].state == FVG_FILLED) continue;
            // Bearish FVG should be above price for sell setup
            if(m_bearFVGs[i].lower <= price) continue;

            double dist = m_bearFVGs[i].lower - price;
            if(dist < minDist) {
                minDist = dist;
                fvg = m_bearFVGs[i];
                found = true;
            }
        }
        return found;
    }

    // Check if price is inside any open FVG
    bool IsPriceInBullishFVG(double price) {
        for(int i = 0; i < ArraySize(m_bullFVGs); i++) {
            if(m_bullFVGs[i].state == FVG_OPEN || m_bullFVGs[i].state == FVG_PARTIAL) {
                if(price >= m_bullFVGs[i].lower && price <= m_bullFVGs[i].upper)
                    return true;
            }
        }
        return false;
    }

    bool IsPriceInBearishFVG(double price) {
        for(int i = 0; i < ArraySize(m_bearFVGs); i++) {
            if(m_bearFVGs[i].state == FVG_OPEN || m_bearFVGs[i].state == FVG_PARTIAL) {
                if(price >= m_bearFVGs[i].lower && price <= m_bearFVGs[i].upper)
                    return true;
            }
        }
        return false;
    }

    // Confidence score for FVG setup (0-100)
    int GetFVGConfidence(ENUM_FVG_TYPE ftype) {
        SFairValueGap fvgs[];
        int count = (ftype == FVG_BULL) ? ArraySize(m_bullFVGs) : ArraySize(m_bearFVGs);
        if(count == 0) return 0;

        int openCount = 0;
        int partialCount = 0;
        double avgSize = 0;

        for(int i = 0; i < count; i++) {
            SFairValueGap &f = (ftype == FVG_BULL) ? m_bullFVGs[i] : m_bearFVGs[i];
            if(f.state == FVG_OPEN) openCount++;
            else if(f.state == FVG_PARTIAL) partialCount++;
            avgSize += f.size;
        }
        avgSize /= count;

        int conf = 30; // Base
        conf += openCount * 15;         // Open gaps are highest value
        conf += partialCount * 8;        // Partial fills still valid
        conf += MathMin(count * 3, 20);  // More historical FVGs = stronger structure
        conf += (avgSize > 500 * Point()) ? 10 : 5; // Larger gaps = stronger

        return MathMin(conf, 100);
    }
};

#endif // ICT_FAIR_VALUE_GAP_MQH
//+------------------------------------------------------------------+
//| END: ICT_FairValueGap.mqh                                         |
//+------------------------------------------------------------------+