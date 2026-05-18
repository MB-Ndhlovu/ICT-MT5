#ifndef ICT_KILL_ZONES_MQH
#define ICT_KILL_ZONES_MQH

enum ENUM_SESSION
  {
   SESSION_NONE=0,
   SESSION_LONDON=1,
   SESSION_NY_OPEN=2,
   SESSION_LONDON_CLOSE=3,
   SESSION_NY_CLOSE=4
  };

enum ENUM_KZ_STATE
  {
   KZ_INACTIVE=0,
   KZ_ACTIVE=1,
   KZ_FADE=2,
   KZ_CLOSING=3
  };

struct SSessionWindow
  {
   ENUM_SESSION session;
   int startHourNY;
   int endHourNY;
   bool isActive;
   double probability;
   int tradesInSession;
   int winsInSession;
  };

class CKillZones
  {
private:
   SSessionWindow m_sessions[];
   int            m_utcOffsetHours;
   int            m_nyOffsetHours;
   int            m_sessionOffsetMinutes;
   bool           m_tradeTakenInSession;
   ENUM_SESSION   m_activeSession;
   ENUM_KZ_STATE  m_state;
   datetime       m_lastSessionDate;

   int NormalizeHour(const int hour) const
     {
      int h=hour%24;
      if(h<0) h+=24;
      return h;
     }

   datetime CurrentShiftedTime(const int offsetHours,const int offsetMinutes) const
     {
      return TimeGMT()+offsetHours*3600+offsetMinutes*60;
     }

   int HourFromShifted(const int offsetHours,const int offsetMinutes) const
     {
      MqlDateTime dt;
      TimeToStruct(CurrentShiftedTime(offsetHours,offsetMinutes),dt);
      return dt.hour;
     }

   bool InRange(const int hour,const int startHour,const int endHour) const
     {
      if(startHour<endHour)
         return hour>=startHour && hour<endHour;
      return hour>=startHour || hour<endHour;
     }

   ENUM_SESSION ResolveSession(const int nyHour) const
     {
      if(InRange(nyHour,3,5))   return SESSION_LONDON;
      if(InRange(nyHour,7,10))  return SESSION_NY_OPEN;
      if(InRange(nyHour,8,10))  return SESSION_LONDON_CLOSE;
      if(InRange(nyHour,15,17)) return SESSION_NY_CLOSE;
      return SESSION_NONE;
     }

   int SessionIndex(const ENUM_SESSION session) const
     {
      for(int i=0;i<ArraySize(m_sessions);i++)
         if(m_sessions[i].session==session) return i;
      return -1;
     }

   double SessionWinRate(const ENUM_SESSION session) const
     {
      const int idx=SessionIndex(session);
      if(idx<0) return 0.5;
      if(m_sessions[idx].tradesInSession<=0) return m_sessions[idx].probability;
      return (double)m_sessions[idx].winsInSession/(double)m_sessions[idx].tradesInSession;
     }

public:
               CKillZones()
        {
         m_utcOffsetHours=2;
         m_nyOffsetHours=-5;
         m_sessionOffsetMinutes=0;
         m_tradeTakenInSession=false;
         m_activeSession=SESSION_NONE;
         m_state=KZ_INACTIVE;
         m_lastSessionDate=0;
         ArrayResize(m_sessions,4);
         m_sessions[0].session=SESSION_LONDON;       m_sessions[0].startHourNY=3;  m_sessions[0].endHourNY=5;  m_sessions[0].probability=0.55;
         m_sessions[1].session=SESSION_NY_OPEN;       m_sessions[1].startHourNY=7;  m_sessions[1].endHourNY=10; m_sessions[1].probability=0.60;
         m_sessions[2].session=SESSION_LONDON_CLOSE;   m_sessions[2].startHourNY=8;  m_sessions[2].endHourNY=10; m_sessions[2].probability=0.50;
         m_sessions[3].session=SESSION_NY_CLOSE;       m_sessions[3].startHourNY=15; m_sessions[3].endHourNY=17; m_sessions[3].probability=0.48;
         for(int i=0;i<ArraySize(m_sessions);i++)
           {
            m_sessions[i].isActive=false;
            m_sessions[i].tradesInSession=0;
            m_sessions[i].winsInSession=0;
           }
        }

   void Init(const int serverUtcOffsetHours=2,const int nyUtcOffsetHours=-5,const int sessionOffsetMinutes=0)
     {
      m_utcOffsetHours=serverUtcOffsetHours;
      m_nyOffsetHours=nyUtcOffsetHours;
      m_sessionOffsetMinutes=sessionOffsetMinutes;
     }

   void Refresh()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      const int nyHour=HourFromShifted(m_nyOffsetHours,m_sessionOffsetMinutes);
      const ENUM_SESSION session=ResolveSession(nyHour);
      m_activeSession=session;
      m_state=KZ_INACTIVE;

      for(int i=0;i<ArraySize(m_sessions);i++)
         m_sessions[i].isActive=(m_sessions[i].session==session);

      if(session!=SESSION_NONE)
        {
         const int idx=SessionIndex(session);
         if(idx>=0)
           {
            const int endHour=m_sessions[idx].endHourNY;
            const int startHour=m_sessions[idx].startHourNY;
            if(InRange(nyHour,endHour-1,endHour) && dt.min>=45)
               m_state=KZ_CLOSING;
            else if(InRange(nyHour,startHour,endHour))
               m_state=KZ_ACTIVE;
            else
               m_state=KZ_FADE;
           }
        }
      else
        {
         m_tradeTakenInSession=false;
        }

      const datetime todayKey=(datetime)StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",dt.year,dt.mon,dt.day));
      if(todayKey!=m_lastSessionDate)
        {
         m_lastSessionDate=todayKey;
         m_tradeTakenInSession=false;
        }
     }

   bool IsKillZoneActive() const
     {
      return m_activeSession!=SESSION_NONE;
     }

   bool IsKillZoneTrue() const
     {
      return m_state==KZ_ACTIVE || m_state==KZ_CLOSING;
     }

   ENUM_SESSION GetActiveSession() const
     {
      return m_activeSession;
     }

   ENUM_KZ_STATE GetState() const
     {
      return m_state;
     }

   double GetSessionProbability() const
     {
      return SessionWinRate(m_activeSession);
     }

   bool CanTradeInSession() const
     {
      return IsKillZoneTrue() && !m_tradeTakenInSession;
     }

   void MarkTradeTaken()
     {
      m_tradeTakenInSession=true;
      const int idx=SessionIndex(m_activeSession);
      if(idx>=0) m_sessions[idx].tradesInSession++;
     }

   void RecordSessionResult(const bool isWin)
     {
      const int idx=SessionIndex(m_activeSession);
      if(idx>=0)
        {
         if(isWin) m_sessions[idx].winsInSession++;
        }
      m_tradeTakenInSession=false;
     }

   ENUM_SESSION GetBestSessionForBias(const bool isBullish) const
     {
      double bestScore=-1.0;
      ENUM_SESSION best=SESSION_NY_OPEN;
      for(int i=0;i<ArraySize(m_sessions);i++)
        {
         double score=SessionWinRate(m_sessions[i].session);
         if(isBullish && m_sessions[i].session==SESSION_NY_OPEN) score+=0.05;
         if(!isBullish && m_sessions[i].session==SESSION_LONDON_CLOSE) score+=0.03;
         if(score>bestScore)
           {
            bestScore=score;
            best=m_sessions[i].session;
           }
        }
      return best;
     }

   int SecondsUntilNextKillZone() const
     {
      const int nyHour=HourFromShifted(m_nyOffsetHours,m_sessionOffsetMinutes);
      const int nyMinute=TimeMinute(CurrentShiftedTime(m_nyOffsetHours,m_sessionOffsetMinutes));
      const int startHours[4]={3,7,8,15};
      int best=24*3600;
      for(int i=0;i<4;i++)
        {
         int target=(startHours[i]*3600)-(nyHour*3600+nyMinute*60);
         if(target<0) target+=24*3600;
         if(target<best) best=target;
        }
      return best;
     }

   void ResetDailySessionTracking()
     {
      for(int i=0;i<ArraySize(m_sessions);i++)
        {
         m_sessions[i].tradesInSession=0;
         m_sessions[i].winsInSession=0;
         m_sessions[i].isActive=false;
        }
      m_tradeTakenInSession=false;
      m_activeSession=SESSION_NONE;
      m_state=KZ_INACTIVE;
     }
  };

#endif
