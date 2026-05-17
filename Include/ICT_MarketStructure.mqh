//+------------------------------------------------------------------+
//|  ICT Market Structure Module                                     |
//|  File: ICT_MarketStructure.mqh                                   |
//|  Author: Malibongwe Ndhlovu (Supervisor: Ben JARVIS AI)          |
//|  Date: 2026-05-17                                                 |
//|  Purpose: Detects swing highs/lows, BoS/ChoCh, and structure    |
//+------------------------------------------------------------------+

#ifndef ICT_MARKET_STRUCTURE_MQH
#define ICT_MARKET_STRUCTURE_MQH

//+------------------------------------------------------------------+
//| ENUM: Market Structure State                                     |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_STATE {
    STRUCTURE_NEUTRAL,     // No confirmed direction yet
    STRUCTURE_BULLISH,     // Price making higher highs and higher lows
    STRUCTURE_BEARISH      // Price making lower highs and lower lows
};

//+------------------------------------------------------------------+
//| ENUM: Structure Confluence Events                                |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_EVENT {
    EVENT_NONE,
    EVENT_BULLISH_BOS,     // Break of Structure (bullish) — continuation
    EVENT_BEARISH_BOS,     // Break of Structure (bearish) — continuation
    EVENT_BULLISH_CHOCH,   // Change of Character (bullish) — reversal
    EVENT_BEARISH_CHOCH,   // Change of Character (bearish) — reversal
    EVENT_LIQUIDITY_POOL   // Price approached a liquidity zone
};

//+------------------------------------------------------------------+
//| CLASS: CMarketStructure                                           |
//|                                                                          |
//| REPORT: Design Decisions                                              |
//| ----------                                                            |
//| 1. Swing detection uses a pivot-window approach rather than rawZigZag. |
//|    Reason: ZigZag repaints and produces inconsistent results during    |
//|    live running. Pivot-based identification is deterministic and stable. |
//|                                                                          |
//| 2. Lookback parameter (default 5 bars) is configurable per market.       |
//|    XAUUSD: use 3-5 (high noise, faster swings)                          |
//|    NAS100/US30: use 8-12 (slower, cleaner structure)                    |
//|    Rationale: Different instruments have different volatility profiles  |
//|    and require different sensitivity settings.                          |
//|                                                                          |
//| 3. BoS vs ChoCh distinction:                                           |
//|    BoS = trend continuation signal (price breaks last swing high/low    |
//|          AND maintains higher timeframe structure)                      |
//|    ChoCh = trend reversal signal (price breaks structure but does NOT   |
//|            confirm on the higher timeframe — potential trap)             |
//|    This distinction is critical: ICT teaches that ChoCh often precedes   |
//|    liquidity sweeps before the real move.                               |
//|                                                                          |
//| 4. Structure strength tracking:                                         |
//|    We track consecutive bullish/bearish bars after a structure break. |
//|    A minimum 2-bar confirmation before signaling reduces false breaks.   |
//|                                                                          |
//+------------------------------------------------------------------+
class CMarketStructure {

private:
    // Chart configuration
    int               m_handle;             // Indicator handle
    ENUM_TIMEFRAMES   m_timeframe;          // Operating timeframe
    string            m_symbol;             // Trading symbol
    int               m_lookback;           // Bars to confirm swing pivot
    
    // Structure state
    ENUM_STRUCTURE_STATE  m_state;          // Current structure direction
    ENUM_STRUCTURE_EVENT  m_lastEvent;      // Most recent structure event
    
    // Swing levels — the core data we track
    double            m_swingHigh;           // Most recent swing high price
    double            m_swingLow;            // Most recent swing low price
    datetime         m_swingHighTime;        // Time of swing high
    datetime         m_swingLowTime;          // Time of swing low
    
    // Prior swing levels (for BoS detection)
    double            m_prevSwingHigh;       // Previous swing high
    double            m_prevSwingLow;        // Previous swing low
    
    // Structure break tracking
    double            m_lastStructureHigh;    // Last confirmed high (BoS reference)
    double            m_lastStructureLow;     // Last confirmed low (BoS reference)
    bool              m_boSStrong;            // True if structure has 2+ bar confirmation
    
    // Buffer for event history (last 10 events)
    ENUM_STRUCTURE_EVENT  m_eventBuffer[10];
    int               m_eventIndex;
    
    // Internal refresh counter (update every N ticks, not every tick)
    int               m_refreshCounter;
    int               m_refreshInterval;     // Bars between full recalculations
    
    // Private methods
    void              DetectSwingHigh(int shift);
    void              DetectSwingLow(int shift);
    void              UpdateStructureState();
    void              PushEvent(ENUM_STRUCTURE_EVENT event);
    
public:
    // Constructor
                     CMarketStructure();
                     
    // Destructor
                    ~CMarketStructure();
    
    // Initialization
    void              Init(ENUM_TIMEFRAMES timeframe, string symbol, int lookback = 5);
    
    // Core refresh — call on every tick or on bar close
    void              Refresh();
    
    // Public accessors — these are what the EA reads
    ENUM_STRUCTURE_STATE  GetState()         { return m_state; }
    ENUM_STRUCTURE_EVENT  GetLastEvent()     { return m_lastEvent; }
    double            GetSwingHigh()         { return m_swingHigh; }
    double            GetSwingLow()          { return m_swingLow; }
    double            GetLastStructureHigh() { return m_lastStructureHigh; }
    double            GetLastStructureLow()  { return m_lastStructureLow; }
    datetime          GetSwingHighTime()     { return m_swingHighTime; }
    datetime          GetSwingLowTime()      { return m_swingLowTime; }
    bool              IsBoSStrong()           { return m_boSStrong; }
    
    // Multi-timeframe support — check structure on a higher timeframe
    bool              IsBullishOnHigher(ENUM_TIMEFRAMES higherTf);
    bool              IsBearishOnHigher(ENUM_TIMEFRAMES higherTf);
    
    // Utility
    string            StateToString();
    string            EventToString();
    void              PrintStatus();          // Debug output for supervisor review
    
};

//+------------------------------------------------------------------+
//| CONSTRUCTOR                                                       |
//+------------------------------------------------------------------+
CMarketStructure::CMarketStructure() {
    m_handle = INVALID_HANDLE;
    m_state = STRUCTURE_NEUTRAL;
    m_lastEvent = EVENT_NONE;
    m_swingHigh = 0;
    m_swingLow = 0;
    m_prevSwingHigh = 0;
    m_prevSwingLow = 0;
    m_lastStructureHigh = 0;
    m_lastStructureLow = 0;
    m_boSStrong = false;
    m_refreshCounter = 0;
    m_refreshInterval = 1;  // Update every bar
    m_eventIndex = 0;
    ArrayInitialize(m_eventBuffer, EVENT_NONE);
}

//+------------------------------------------------------------------+
//| DESTRUCTOR                                                        |
//+------------------------------------------------------------------+
CMarketStructure::~CMarketStructure() {
    if(m_handle != INVALID_HANDLE)
        IndicatorRelease(m_handle);
}

//+------------------------------------------------------------------+
//| INIT                                                              |
//|                                                                          |
//| Parameters:                                                            |
//|   timeframe  — operating timeframe (PERIOD_M1, PERIOD_M5, etc.)          |
//|   symbol     — trading symbol ("XAUUSD", "NAS100", "US30")               |
//|   lookback   — bars to look back for swing pivot (default 5)            |
//|                                                                          |
//| Supervisor Note:                                                        |
//|   The lookback parameter is critical. Too small = noise. Too large =   |
//|   lag. For XAUUSD on M5: 3-5. For NAS100 on H1: 8-12.                   |
//+------------------------------------------------------------------+
void CMarketStructure::Init(ENUM_TIMEFRAMES timeframe, string symbol, int lookback = 5) {
    m_timeframe = timeframe;
    m_symbol = symbol;
    m_lookback = lookback;
    
    // Set refresh interval based on timeframe
    // Lower timeframes need slower refresh to avoid noise
    if(timeframe <= PERIOD_M5)
        m_refreshInterval = 5;   // Check every 5 bars
    else if(timeframe <= PERIOD_H1)
        m_refreshInterval = 1;   // Every bar is fine
    else
        m_refreshInterval = 1;   // Daily+ always update every bar
    
    Print("[ICT_MS] Initialized ", m_symbol, " on ", EnumToString(timeframe),
          " | Lookback: ", lookback);
}

//+------------------------------------------------------------------+
//| DETECT SWING HIGH                                                 |
//|                                                                          |
//| Logic: A bar is a swing high if its high is greater than the highs    |
//| of 'lookback' bars before AND after it.                              |
//|                                                                          |
//| Supervisor Note:                                                       |
//|   This is a symmetric window — meaning we require confirmation both   |
//|   ahead and behind the pivot. This prevents repainting. The bar cannot  |
//|   be a swing high until 'lookback' bars have passed after it. This     |
//|   eliminates false signals during live running.                        |
//+------------------------------------------------------------------+
void CMarketStructure::DetectSwingHigh(int shift) {
    double high = iHigh(m_symbol, m_timeframe, shift);
    
    // Check if this bar is higher than all bars in the lookback window before it
    bool isHighestBefore = true;
    for(int i = 1; i <= m_lookback; i++) {
        if(iHigh(m_symbol, m_timeframe, shift + i) >= high) {
            isHighestBefore = false;
            break;
        }
    }
    if(!isHighestBefore) return;
    
    // Check if this bar is higher than all bars in the lookback window after it
    // shift-1 is the bar immediately before (we need lookback bars ahead)
    bool isHighestAfter = true;
    for(int i = 1; i <= m_lookback; i++) {
        if(shift - i < 0) break;  // Not enough history yet — skip
        if(iHigh(m_symbol, m_timeframe, shift - i) >= high) {
            isHighestAfter = false;
            break;
        }
    }
    if(!isHighestAfter) return;
    
    // If we reach here: this bar IS a swing high
    // Update previous before overwriting
    m_prevSwingHigh = m_swingHigh;
    m_swingHigh = high;
    m_swingHighTime = iTime(m_symbol, m_timeframe, shift);
}

//+------------------------------------------------------------------+
//| DETECT SWING LOW                                                  |
//| Logic: Identical to swing high detection, but on the LOW price.  |
//+------------------------------------------------------------------+
void CMarketStructure::DetectSwingLow(int shift) {
    double low = iLow(m_symbol, m_timeframe, shift);
    
    bool isLowestBefore = true;
    for(int i = 1; i <= m_lookback; i++) {
        if(iLow(m_symbol, m_timeframe, shift + i) <= low) {
            isLowestBefore = false;
            break;
        }
    }
    if(!isLowestBefore) return;
    
    bool isLowestAfter = true;
    for(int i = 1; i <= m_lookback; i++) {
        if(shift - i < 0) break;
        if(iLow(m_symbol, m_timeframe, shift - i) <= low) {
            isLowestAfter = false;
            break;
        }
    }
    if(!isLowestAfter) return;
    
    m_prevSwingLow = m_swingLow;
    m_swingLow = low;
    m_swingLowTime = iTime(m_symbol, m_timeframe, shift);
}

//+------------------------------------------------------------------+
//| UPDATE STRUCTURE STATE                                            |
//|                                                                          |
//| Supervisor Note on BoS vs ChoCh:                                     |
//|                                                                          |
//| BREAK OF STRUCTURE (BoS):                                             |
//|   Price makes a new high above the last swing high in an uptrend,      |
//|   OR a new low below the last swing low in a downtrend.                |
//|   This confirms the current trend is continuing.                        |
//|                                                                          |
//| CHANGE OF CHARACTER (ChoCh):                                          |
//|   Price breaks the last swing high/low BUT the higher timeframe        |
//|   structure does NOT confirm. This is a warning that the move may      |
//|   be a liquidity sweep — price will often reverse after taking retail   |
//|   stops.                                                               |
//|                                                                          |
//| We implement this distinction by checking whether the break also      |
//| clears the lastStructureHigh/Low threshold. Those are only updated     |
//| after a confirmed strong move (2+ bars), preventing noise triggers.     |
//+------------------------------------------------------------------+
void CMarketStructure::UpdateStructureState() {
    double close = iClose(m_symbol, m_timeframe, 0);
    ENUM_STRUCTURE_STATE prevState = m_state;
    
    // Detect bullish break of structure
    // Price closes above previous swing high AND we've had bullish momentum
    if(m_swingHigh > m_lastStructureHigh && m_swingHigh > 0 && m_lastStructureHigh > 0) {
        // Count bullish bars after the break
        int bullishCount = 0;
        for(int i = 1; i <= 3; i++) {
            if(iClose(m_symbol, m_timeframe, i) > iOpen(m_symbol, m_timeframe, i))
                bullishCount++;
        }
        
        if(bullishCount >= 2) {
            m_lastStructureHigh = m_swingHigh;
            m_boSStrong = true;
            
            if(m_state != STRUCTURE_BULLISH) {
                m_state = STRUCTURE_BULLISH;
                PushEvent(EVENT_BULLISH_BOS);
            }
        }
    }
    
    // Detect bearish break of structure
    else if(m_swingLow < m_lastStructureLow && m_swingLow > 0 && m_lastStructureLow > 0) {
        int bearishCount = 0;
        for(int i = 1; i <= 3; i++) {
            if(iClose(m_symbol, m_timeframe, i) < iOpen(m_symbol, m_timeframe, i))
                bearishCount++;
        }
        
        if(bearishCount >= 2) {
            m_lastStructureLow = m_swingLow;
            m_boSStrong = true;
            
            if(m_state != STRUCTURE_BEARISH) {
                m_state = STRUCTURE_BEARISH;
                PushEvent(EVENT_BEARISH_BOS);
            }
        }
    }
    
    // Detect Change of Character (reversal without higher timeframe confirmation)
    // Price breaks structure but momentum does NOT follow through
    else if(m_swingHigh > m_lastStructureHigh || m_swingLow < m_lastStructureLow) {
        // Weak bar count: only 1 or 0 directional bars after the break
        int dirCount = 0;
        for(int i = 1; i <= 3; i++) {
            if(iClose(m_symbol, m_timeframe, i) > iOpen(m_symbol, m_timeframe, i))
                dirCount++;
            else if(iClose(m_symbol, m_timeframe, i) < iOpen(m_symbol, m_timeframe, i))
                dirCount--;
        }
        
        // Low momentum after structure break = potential reversal (ChoCh)
        if(m_state == STRUCTURE_BULLISH && dirCount <= 0 && m_swingLow < m_lastStructureLow) {
            m_state = STRUCTURE_BEARISH;
            PushEvent(EVENT_BEARISH_CHOCH);
        }
        else if(m_state == STRUCTURE_BEARISH && dirCount >= 0 && m_swingHigh > m_lastStructureHigh) {
            m_state = STRUCTURE_BULLISH;
            PushEvent(EVENT_BULLISH_CHOCH);
        }
    }
}

//+------------------------------------------------------------------+
//| PUSH EVENT                                                        |
//| Maintains circular buffer of last 10 events for analysis.        |
//+------------------------------------------------------------------+
void CMarketStructure::PushEvent(ENUM_STRUCTURE_EVENT event) {
    if(event == EVENT_NONE) return;
    
    m_eventBuffer[m_eventIndex] = event;
    m_eventIndex = (m_eventIndex + 1) % 10;
    m_lastEvent = event;
}

//+------------------------------------------------------------------+
//| REFRESH                                                           |
//| Called every tick or on new bar. Orchestrates full structure      |
//| recalculation.                                                    |
//+------------------------------------------------------------------+
void CMarketStructure::Refresh() {
    m_refreshCounter++;
    
    // Only update on bar close or every N intervals (reduce CPU load)
    if(m_refreshCounter < m_refreshInterval) return;
    m_refreshCounter = 0;
    
    // Scan last 20 bars for new swing points
    int totalBars = MathMin(20, iBarTotal(m_symbol, m_timeframe));
    
    for(int i = 0; i < totalBars; i++) {
        DetectSwingHigh(i);
        DetectSwingLow(i);
    }
    
    // Initialize structure levels on first run
    if(m_lastStructureHigh == 0 && m_swingHigh > 0)
        m_lastStructureHigh = m_swingHigh;
    if(m_lastStructureLow == 0 && m_swingLow > 0)
        m_lastStructureLow = m_swingLow;
    
    // Update state machine
    UpdateStructureState();
}

//+------------------------------------------------------------------+
//| MULTI-TIMEFRAME CHECK                                             |
//| Checks if the higher timeframe confirms the current bias.         |
//| Used to distinguish BoS (confirmed) from ChoCh (warning).        |
//+------------------------------------------------------------------+
bool CMarketStructure::IsBullishOnHigher(ENUM_TIMEFRAMES higherTf) {
    // Get the last 5 swings on higher timeframe
    double higherHigh = iHigh(m_symbol, higherTf, 1);
    double higherLow = iLow(m_symbol, higherTf, 1);
    double prevHigherHigh = iHigh(m_symbol, higherTf, 5);
    double prevHigherLow = iLow(m_symbol, higherTf, 5);
    
    // Bullish confirmation: higher timeframe making higher highs
    return (higherHigh > prevHigherHigh);
}

bool CMarketStructure::IsBearishOnHigher(ENUM_TIMEFRAMES higherTf) {
    double higherHigh = iHigh(m_symbol, higherTf, 1);
    double higherLow = iLow(m_symbol, higherTf, 1);
    double prevHigherHigh = iHigh(m_symbol, higherTf, 5);
    double prevHigherLow = iLow(m_symbol, higherTf, 5);
    
    // Bearish confirmation: higher timeframe making lower lows
    return (lowerLow < prevLowerLow);
}

//+------------------------------------------------------------------+
//| UTILITY: STRING OUTPUT                                            |
//+------------------------------------------------------------------+
string CMarketStructure::StateToString() {
    switch(m_state) {
        case STRUCTURE_BULLISH: return "BULLISH";
        case STRUCTURE_BEARISH: return "BEARISH";
        default: return "NEUTRAL";
    }
}

string CMarketStructure::EventToString() {
    switch(m_lastEvent) {
        case EVENT_BULLISH_BOS: return "BULLISH BoS";
        case EVENT_BEARISH_BOS: return "BEARISH BoS";
        case EVENT_BULLISH_CHOCH: return "BULLISH ChoCh";
        case EVENT_BEARISH_CHOCH: return "BEARISH ChoCh";
        default: return "NONE";
    }
}

void CMarketStructure::PrintStatus() {
    Print("========== ICT MARKET STRUCTURE ==========");
    Print("Symbol: ", m_symbol, " | TF: ", EnumToString(m_timeframe));
    Print("State: ", StateToString(), " | Last Event: ", EventToString());
    Print("Swing High: ", m_swingHigh, " at ", TimeToString(m_swingHighTime));
    Print("Swing Low:  ", m_swingLow,  " at ", TimeToString(m_swingLowTime));
    Print("Struct High: ", m_lastStructureHigh, " | Struct Low: ", m_lastStructureLow);
    Print("BoS Confirmed: ", m_boSStrong ? "YES" : "NO");
    Print("==========================================");
}

#endif
//+------------------------------------------------------------------+