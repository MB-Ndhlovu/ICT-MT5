//+------------------------------------------------------------------+
//|  ICT Kill Zones Module                                            |
//|  File: ICT_KillZones.mqh                                          |
//|  Author: Malibongwe Ndhlovu                                       |
//|  Supervisor: Ben JARVIS AI                                        |
//|  Date: 2026-05-17                                                 |
//+------------------------------------------------------------------+

#ifndef ICT_KILL_ZONES_MQH
#define ICT_KILL_ZONES_MQH

//+------------------------------------------------------------------+
//| ENUM: Session Type                                                |
//+------------------------------------------------------------------+
enum ENUM_SESSION {
    SESSION_NONE,
    SESSION_LONDON,     // 03:00-05:00 NY = 10:00-12:00 SAST
    SESSION_NY_OPEN,    // 07:00-10:00 NY = 14:00-17:00 SAST
    SESSION_LONDON_CLOSE, // 08:00-10:00 NY = 15:00-17:00 SAST
    SESSION_NY_CLOSE    // 15:00-17:00 NY = 22:00-00:00 SAST
};

//+------------------------------------------------------------------+
//| ENUM: Kill Zone State                                             |
//+------------------------------------------------------------------+
enum ENUM_KZ_STATE {
    KZ_INACTIVE,        // Outside kill zone
    KZ_ACTIVE,          // Inside kill zone, high probability
    KZ_FADE,            // Kill zone but conditions not favorable
    KZ_CLOSING          // Last 15 min of kill zone, take profits
};

//+------------------------------------------------------------------+
//| STRUCT: Session Window                                            |
//+------------------------------------------------------------------+
struct SSessionWindow {
    ENUM_SESSION session;
    int          startHourNY;    // Start hour in NY time (0-23)
    int          endHourNY;      // End hour in NY time (0-23)
    bool         isActive;
    double       probability;    // Historical win rate in this session
    int          tradesInSession; // Session trade count
    int          winsInSession;  // Session wins
};

//+------------------------------------------------------------------+
//| CLASS: CKillZones                                                 |
//+------------------------------------------------------------------+
class CKillZones {
private:
    SSessionWindow m_sessions[];
    datetime       m_lastTradeTime;
    bool           m_tradeTakenInSession;
    int            m_maxTradesPerSession;

    // Convert server time to NY time
    datetime ServerToNYTime(datetime serverTime) {
        // NYC is UTC-4 (EDT) or UTC-5 (EST) depending on DST
        // MQL5: _TimeGMT is the server's GMT time
        datetime nyTime = serverTime - 5 * 3600; // Approximate UTC-5 (EST)
        MqlDateTime dt;
        TimeToStruct(nyTime, dt);
        return nyTime;
    }

    // Check if NY time is within session range
    bool IsInSessionRange(int nyHour, int startHour, int endHour) {
        if(startHour < endHour)
            return nyHour >= startHour && nyHour < endHour;
        else
            return nyHour >= startHour || nyHour < endHour; // Wraps midnight
    }

    // Get current session
    ENUM_SESSION GetCurrentSession(int nyHour) {
        if(IsInSessionRange(nyHour, 3, 5))  return SESSION_LONDON;
        if(IsInSessionRange(nyHour, 7, 10)) return SESSION_NY_OPEN;
        if(IsInSessionRange(nyHour, 8, 10))  return SESSION_LONDON_CLOSE;
        if(IsInSessionRange(nyHour, 15, 17)) return SESSION_NY_CLOSE;
        return SESSION_NONE;
    }

    // Calculate session probability based on historical performance
    double CalculateSessionProbability(ENUM_SESSION session) {
        for(int i = 0; i < ArraySize(m_sessions); i++) {
            if(m_sessions[i].session == session) {
                if(m_sessions[i].tradesInSession == 0) return 0.5; // Default 50%
                return (double)m_sessions[i].winsInSession / m_sessions[i].tradesInSession;
            }
        }
        return 0.5;
    }

public:
    CKillZones() {
        m_maxTradesPerSession = 2;
        m_tradeTakenInSession = false;
        m_lastTradeTime = 0;
        ArrayResize(m_sessions, 4);

        // London Open — 03:00-05:00 NY
        m_sessions[0].session         = SESSION_LONDON;
        m_sessions[0].startHourNY      = 3;
        m_sessions[0].endHourNY        = 5;
        m_sessions[0].probability      = 0.55;
        m_sessions[0].tradesInSession  = 0;
        m_sessions[0].winsInSession     = 0;

        // NY Open — 07:00-10:00 NY (highest probability)
        m_sessions[1].session         = SESSION_NY_OPEN;
        m_sessions[1].startHourNY     = 7;
        m_sessions[1].endHourNY        = 10;
        m_sessions[1].probability      = 0.60;
        m_sessions[1].tradesInSession  = 0;
        m_sessions[1].winsInSession    = 0;

        // London Close — 08:00-10:00 NY
        m_sessions[2].session         = SESSION_LONDON_CLOSE;
        m_sessions[2].startHourNY     = 8;
        m_sessions[2].endHourNY        = 10;
        m_sessions[2].probability      = 0.50;
        m_sessions[2].tradesInSession  = 0;
        m_sessions[2].winsInSession    = 0;

        // NY Close — 15:00-17:00 NY
        m_sessions[3].session         = SESSION_NY_CLOSE;
        m_sessions[3].startHourNY     = 15;
        m_sessions[3].endHourNY        = 17;
        m_sessions[3].probability      = 0.48;
        m_sessions[3].tradesInSession  = 0;
        m_sessions[3].winsInSession     = 0;
    }

    // Refresh — call every tick to update session state
    void Refresh() {
        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);

        // Get NY hour (simplified — actual implementation would use Holiday lib)
        int nyHour = (dt.hour + 20) % 24; // SAST (UTC+2) = UTC+2, NYC = UTC-5 → offset = 7 hours, but we simplify

        ENUM_SESSION currentSession = GetCurrentSession(dt.hour);
        ENUM_KZ_STATE state = KZ_INACTIVE;

        if(currentSession != SESSION_NONE) {
            // Check if within last 15 min (fade/kill zone closing)
            int hour = dt.hour;
            for(int i = 0; i < ArraySize(m_sessions); i++) {
                if(m_sessions[i].session == currentSession) {
                    if(dt.hour == m_sessions[i].endHourNY - 1 && dt.min >= 45)
                        state = KZ_CLOSING;
                    else
                        state = KZ_ACTIVE;
                    m_sessions[i].isActive = true;
                    break;
                }
            }
        }

        // Reset if new session
        if(currentSession == SESSION_NONE)
            m_tradeTakenInSession = false;
    }

    // Is kill zone active right now?
    bool IsKillZoneActive() {
        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);

        ENUM_SESSION sess = GetCurrentSession(dt.hour);
        return sess != SESSION_NONE;
    }

    // Get current active session
    ENUM_SESSION GetActiveSession() {
        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);
        return GetCurrentSession(dt.hour);
    }

    // Get probability of current session
    double GetSessionProbability() {
        ENUM_SESSION sess = GetActiveSession();
        return CalculateSessionProbability(sess);
    }

    // Can we take a trade in this session?
    bool CanTradeInSession() {
        return IsKillZoneActive() && !m_tradeTakenInSession;
    }

    // Mark trade as taken in this session
    void MarkTradeTaken() {
        m_tradeTakenInSession = true;
        m_lastTradeTime = TimeCurrent();

        ENUM_SESSION sess = GetActiveSession();
        for(int i = 0; i < ArraySize(m_sessions); i++) {
            if(m_sessions[i].session == sess) {
                m_sessions[i].tradesInSession++;
                break;
            }
        }
    }

    // Record session win/loss
    void RecordSessionResult(bool isWin) {
        ENUM_SESSION sess = GetActiveSession();
        for(int i = 0; i < ArraySize(m_sessions); i++) {
            if(m_sessions[i].session == sess) {
                if(isWin) m_sessions[i].winsInSession++;
                m_tradeTakenInSession = false; // Reset for next session
                break;
            }
        }
    }

    // Get best session for a given bias
    ENUM_SESSION GetBestSessionForBias(bool isBullish) {
        double bestProb = 0;
        ENUM_SESSION best = SESSION_NY_OPEN;

        for(int i = 0; i < ArraySize(m_sessions); i++) {
            double prob = CalculateSessionProbability(m_sessions[i].session);
            if(prob > bestProb) {
                bestProb = prob;
                best = m_sessions[i].session;
            }
        }
        return best;
    }

    // Get time until next kill zone (in seconds)
    int SecondsUntilNextKillZone() {
        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);

        // Check London Open (next day if before 3am NY)
        if(dt.hour < 3) {
            return (3 - dt.hour - 1) * 3600 + (60 - dt.min) * 60;
        }
        return 0; // Kill zone active or within 24h
    }

    // Reset session tracking (call at start of new trading day)
    void ResetDailySessionTracking() {
        for(int i = 0; i < ArraySize(m_sessions); i++) {
            m_sessions[i].tradesInSession = 0;
            m_sessions[i].winsInSession   = 0;
            m_sessions[i].isActive        = false;
        }
        m_tradeTakenInSession = false;
    }
};

#endif // ICT_KILL_ZONES_MQH
//+------------------------------------------------------------------+
//| END: ICT_KillZones.mqh                                           |
//+------------------------------------------------------------------+