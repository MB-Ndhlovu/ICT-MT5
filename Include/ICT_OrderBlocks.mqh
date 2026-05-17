//+------------------------------------------------------------------+
//|  ICT Order Blocks Module                                          |
//|  File: ICT_OrderBlocks.mqh                                        |
//|  Author: Malibongwe Ndhlovu                                       |
//|  Supervisor: Ben JARVIS AI                                        |
//|  Date: 2026-05-17                                                 |
//+------------------------------------------------------------------+

#ifndef ICT_ORDER_BLOCKS_MQH
#define ICT_ORDER_BLOCKS_MQH

#include <ICT_MarketStructure.mqh>

//+------------------------------------------------------------------+
//| ENUM: Order Block Type                                            |
//+------------------------------------------------------------------+
enum ENUM_OB_TYPE {
    OB_BULL,   // Bullish OB — institutional buy orders
    OB_BEAR    // Bearish OB — institutional sell orders
};

//+------------------------------------------------------------------+
//| ENUM: OB State                                                    |
//+------------------------------------------------------------------+
enum ENUM_OB_STATE {
    OB_PENDING,  // OB identified but price not retested yet
    OB_ACTIVE,   // Price in OB zone, valid for entry
    OB_WEAKENING,// Price has lingered, OB less valid
    OB_BROKEN    // Price has swept through OB entirely
};

//+------------------------------------------------------------------+
//| STRUCT: Order Block                                               |
//+------------------------------------------------------------------+
struct SOrderBlock {
    double  upper;          // Top of the OB zone
    double  lower;          // Bottom of the OB zone
    int     triggerBar;     // Bar index where OB was triggered
    ENUM_OB_TYPE type;      // Bullish or Bearish
    ENUM_OB_STATE state;    // Current OB state
    double  volume;         // Volume at formation (institutional footprint)
    datetime time;          // Time of formation
    double  efficiency;    // How cleanly price left the OB (0-1)
};

//+------------------------------------------------------------------+
//| CLASS: COrderBlocks                                               |
//+------------------------------------------------------------------+
class COrderBlocks {
private:
    string            m_symbol;
    ENUM_TIMEFRAMES   m_timeframe;
    int               m_maxOBs;          // Max OBs to track
    SOrderBlock       m_obBulls[];       // Bullish OBs
    SOrderBlock       m_obBears[];       // Bearish OBs
    CMarketStructure *m_struct;          // Reference to market structure

    // Helper: calculate volume of a bar
    double VolumeOfBar(int index) {
        return (double)iVolume(m_symbol, m_timeframe, index);
    }

    // Helper: is bar bullish?
    bool IsBullishBar(int index) {
        return iClose(m_symbol, m_timeframe, index) > iOpen(m_symbol, m_timeframe, index);
    }

    // Helper: is bar bearish?
    bool IsBearishBar(int index) {
        return iClose(m_symbol, m_timeframe, index) < iOpen(m_symbol, m_timeframe, index);
    }

    // Calculate efficiency — how much of the bar's range moved in impulse direction
    double CalculateEfficiency(int index, bool bullish) {
        double range = iHigh(m_symbol, m_timeframe, index) - iLow(m_symbol, m_timeframe, index);
        if(range == 0) return 0;
        double body = MathAbs(iClose(m_symbol, m_timeframe, index) - iOpen(m_symbol, m_timeframe, index));
        return body / range; // 0 = doji, 1 = full body
    }

    // Detect a new bullish OB
    bool DetectBullishOB(int triggerBar) {
        // A bullish OB is the last bearish candle BEFORE a strong bullish impulse
        // The impulse must have significant momentum (2+ bullish bars with rising volume)

        if(!IsBearishBar(triggerBar)) return false;

        // Check next 1-3 bars for bullish impulse
        int impulseBars = 0;
        double avgVolume = 0;
        for(int i = triggerBar - 1; i >= 1 && i >= triggerBar - 3; i--) {
            if(IsBullishBar(i)) {
                impulseBars++;
                avgVolume += VolumeOfBar(i);
            }
        }

        if(impulseBars < 2) return false;

        // Calculate OB zone: use the trigger bar's range
        SOrderBlock ob;
        ob.upper       = iHigh(m_symbol, m_timeframe, triggerBar);
        ob.lower       = iLow(m_symbol, m_timeframe, triggerBar);
        ob.triggerBar  = triggerBar;
        ob.type        = OB_BULL;
        ob.state       = OB_PENDING;
        ob.volume      = avgVolume / MathMin(impulseBars, 3);
        ob.time        = iTime(m_symbol, m_timeframe, triggerBar);
        ob.efficiency  = CalculateEfficiency(triggerBar, false); // Bearish bar efficiency

        // Add to array
        int size = ArraySize(m_obBulls);
        ArrayResize(m_obBulls, size + 1);
        m_obBulls[size] = ob;

        // Trim if exceeds max
        if(ArraySize(m_obBulls) > m_maxOBs) {
            for(int i = 0; i < ArraySize(m_obBulls) - 1; i++)
                m_obBulls[i] = m_obBulls[i + 1];
            ArrayResize(m_obBulls, m_maxOBs);
        }

        return true;
    }

    // Detect a new bearish OB
    bool DetectBearishOB(int triggerBar) {
        // A bearish OB is the last bullish candle BEFORE a strong bearish impulse

        if(!IsBullishBar(triggerBar)) return false;

        int impulseBars = 0;
        double avgVolume = 0;
        for(int i = triggerBar - 1; i >= 1 && i >= triggerBar - 3; i--) {
            if(IsBearishBar(i)) {
                impulseBars++;
                avgVolume += VolumeOfBar(i);
            }
        }

        if(impulseBars < 2) return false;

        SOrderBlock ob;
        ob.upper      = iHigh(m_symbol, m_timeframe, triggerBar);
        ob.lower      = iLow(m_symbol, m_timeframe, triggerBar);
        ob.triggerBar = triggerBar;
        ob.type       = OB_BEAR;
        ob.state      = OB_PENDING;
        ob.volume     = avgVolume / MathMin(impulseBars, 3);
        ob.time       = iTime(m_symbol, m_timeframe, triggerBar);
        ob.efficiency = CalculateEfficiency(triggerBar, true); // Bullish bar efficiency

        int size = ArraySize(m_obBears);
        ArrayResize(m_obBears, size + 1);
        m_obBears[size] = ob;

        if(ArraySize(m_obBears) > m_maxOBs) {
            for(int i = 0; i < ArraySize(m_obBears) - 1; i++)
                m_obBears[i] = m_obBears[i + 1];
            ArrayResize(m_obBears, m_maxOBs);
        }

        return true;
    }

    // Update OB states based on current price
    void UpdateOBStates(double bid) {
        // Bullish OBs
        for(int i = 0; i < ArraySize(m_obBulls); i++) {
            if(m_obBulls[i].state == OB_PENDING || m_obBulls[i].state == OB_ACTIVE) {
                if(bid >= m_obBulls[i].lower && bid <= m_obBulls[i].upper)
                    m_obBulls[i].state = OB_ACTIVE;
                else if(bid < m_obBulls[i].lower)
                    m_obBulls[i].state = OB_WEAKENING;
                else if(bid > m_obBulls[i].upper)
                    m_obBulls[i].state = OB_BROKEN;
            }
        }
        // Bearish OBs
        for(int i = 0; i < ArraySize(m_obBears); i++) {
            if(m_obBears[i].state == OB_PENDING || m_obBears[i].state == OB_ACTIVE) {
                if(bid <= m_obBears[i].upper && bid >= m_obBears[i].lower)
                    m_obBears[i].state = OB_ACTIVE;
                else if(bid > m_obBears[i].upper)
                    m_obBears[i].state = OB_WEAKENING;
                else if(bid < m_obBears[i].lower)
                    m_obBears[i].state = OB_BROKEN;
            }
        }
    }

public:
    // Constructor
    COrderBlocks() {
        m_maxOBs = 10;
    }

    // Initialize with symbol and timeframe
    void Init(string symbol, ENUM_TIMEFRAMES timeframe, CMarketStructure *structRef) {
        m_symbol    = symbol;
        m_timeframe = timeframe;
        m_struct    = structRef;
        ArrayResize(m_obBulls, 0);
        ArrayResize(m_obBears, 0);
    }

    // Main refresh — detect new OBs and update states
    void Refresh(int lookback = 20) {
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        for(int i = 1; i <= lookback && i < iBars(m_symbol, m_timeframe); i++) {
            DetectBullishOB(i);
            DetectBearishOB(i);
        }

        UpdateOBStates(bid);
    }

    // Get the nearest active bullish OB
    bool GetNearestBullishOB(double price, SOrderBlock &ob) {
        double minDist = DBL_MAX;
        bool found = false;

        for(int i = 0; i < ArraySize(m_obBulls); i++) {
            if(m_obBulls[i].state != OB_ACTIVE && m_obBulls[i].state != OB_PENDING)
                continue;

            double dist = MathAbs(price - m_obBulls[i].lower);
            if(dist < minDist) {
                minDist = dist;
                ob = m_obBulls[i];
                found = true;
            }
        }
        return found;
    }

    // Get the nearest active bearish OB
    bool GetNearestBearishOB(double price, SOrderBlock &ob) {
        double minDist = DBL_MAX;
        bool found = false;

        for(int i = 0; i < ArraySize(m_obBears); i++) {
            if(m_obBears[i].state != OB_ACTIVE && m_obBears[i].state != OB_PENDING)
                continue;

            double dist = MathAbs(price - m_obBears[i].upper);
            if(dist < minDist) {
                minDist = dist;
                ob = m_obBears[i];
                found = true;
            }
        }
        return found;
    }

    // Check if price is inside any bullish OB zone
    bool IsPriceInBullishOBZone(double price) {
        for(int i = 0; i < ArraySize(m_obBulls); i++) {
            if(m_obBulls[i].state == OB_ACTIVE || m_obBulls[i].state == OB_PENDING) {
                if(price >= m_obBulls[i].lower && price <= m_obBulls[i].upper)
                    return true;
            }
        }
        return false;
    }

    // Check if price is inside any bearish OB zone
    bool IsPriceInBearishOBZone(double price) {
        for(int i = 0; i < ArraySize(m_obBears); i++) {
            if(m_obBears[i].state == OB_ACTIVE || m_obBears[i].state == OB_PENDING) {
                if(price >= m_obBears[i].lower && price <= m_obBears[i].upper)
                    return true;
            }
        }
        return false;
    }

    // Count active OBs
    int CountActiveBullishOBs() {
        int count = 0;
        for(int i = 0; i < ArraySize(m_obBulls); i++)
            if(m_obBulls[i].state == OB_ACTIVE) count++;
        return count;
    }

    int CountActiveBearishOBs() {
        int count = 0;
        for(int i = 0; i < ArraySize(m_obBears); i++)
            if(m_obBears[i].state == OB_ACTIVE) count++;
        return count;
    }

    // Draw OBs on chart (for visual confirmation)
    void DrawOBs(int handle) {
        // Note: Drawing objects in MQL5 requires ChartObject functions
        // This method is for visual debugging — remove for production
    }
};

#endif // ICT_ORDER_BLOCKS_MQH
//+------------------------------------------------------------------+
//| END: ICT_OrderBlocks.mqh                                         |
//+------------------------------------------------------------------+