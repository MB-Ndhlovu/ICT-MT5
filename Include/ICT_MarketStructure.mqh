#ifndef ICT_MARKET_STRUCTURE_MQH
#define ICT_MARKET_STRUCTURE_MQH

#ifndef __MQL5__
#endif

enum ENUM_STRUCTURE_STATE
  {
   STRUCTURE_NEUTRAL=0,
   STRUCTURE_BULLISH=1,
   STRUCTURE_BEARISH=2
  };

enum ENUM_STRUCTURE_EVENT
  {
   EVENT_NONE=0,
   EVENT_BULLISH_BOS=1,
   EVENT_BEARISH_BOS=2,
   EVENT_BULLISH_CHOCH=3,
   EVENT_BEARISH_CHOCH=4,
   EVENT_LIQUIDITY_POOL=5
  };

class CMarketStructure
  {
private:
   string              m_symbol;
   ENUM_TIMEFRAMES     m_timeframe;
   ENUM_TIMEFRAMES     m_alignmentTf;
   int                 m_lookback;
   int                 m_scanDepth;
   ENUM_STRUCTURE_STATE m_state;
   ENUM_STRUCTURE_EVENT m_lastEvent;
   double              m_swingHigh;
   double              m_swingLow;
   datetime            m_swingHighTime;
   datetime            m_swingLowTime;
   double              m_prevSwingHigh;
   double              m_prevSwingLow;
   double              m_lastStructureHigh;
   double              m_lastStructureLow;
   bool                m_boSStrong;
   ENUM_STRUCTURE_EVENT m_eventBuffer[10];
   int                 m_eventIndex;
   datetime            m_lastBarTime;

   bool IsSwingHigh(const int shift) const
     {
      const int bars=iBars(m_symbol,m_timeframe);
      if(bars<=shift+m_lookback || shift<m_lookback)
         return false;
      const double high=iHigh(m_symbol,m_timeframe,shift);
      for(int i=1;i<=m_lookback;i++)
        {
         if(iHigh(m_symbol,m_timeframe,shift-i)>=high) return false;
         if(iHigh(m_symbol,m_timeframe,shift+i)>=high) return false;
        }
      return high>0.0;
     }

   bool IsSwingLow(const int shift) const
     {
      const int bars=iBars(m_symbol,m_timeframe);
      if(bars<=shift+m_lookback || shift<m_lookback)
         return false;
      const double low=iLow(m_symbol,m_timeframe,shift);
      for(int i=1;i<=m_lookback;i++)
        {
         if(iLow(m_symbol,m_timeframe,shift-i)<=low) return false;
         if(iLow(m_symbol,m_timeframe,shift+i)<=low) return false;
        }
      return low>0.0;
     }

   void PushEvent(const ENUM_STRUCTURE_EVENT event)
     {
      if(event==EVENT_NONE)
         return;
      m_eventBuffer[m_eventIndex]=event;
      m_eventIndex=(m_eventIndex+1)%10;
      m_lastEvent=event;
     }

   void UpdateRecentSwings()
     {
      const int bars=iBars(m_symbol,m_timeframe);
      if(bars<=m_lookback*2+2)
         return;

      double foundHigh=0.0, foundLow=0.0, prevHigh=0.0, prevLow=0.0;
      datetime foundHighTime=0, foundLowTime=0, prevHighTime=0, prevLowTime=0;
      const int limit=MathMin(bars-m_lookback-1,m_scanDepth);
      for(int shift=m_lookback+1; shift<=limit; shift++)
        {
         if(foundHighTime==0 && IsSwingHigh(shift))
           {
            foundHigh=iHigh(m_symbol,m_timeframe,shift);
            foundHighTime=iTime(m_symbol,m_timeframe,shift);
           }
         else if(foundHighTime!=0 && prevHighTime==0 && IsSwingHigh(shift))
           {
            prevHigh=iHigh(m_symbol,m_timeframe,shift);
            prevHighTime=iTime(m_symbol,m_timeframe,shift);
           }

         if(foundLowTime==0 && IsSwingLow(shift))
           {
            foundLow=iLow(m_symbol,m_timeframe,shift);
            foundLowTime=iTime(m_symbol,m_timeframe,shift);
           }
         else if(foundLowTime!=0 && prevLowTime==0 && IsSwingLow(shift))
           {
            prevLow=iLow(m_symbol,m_timeframe,shift);
            prevLowTime=iTime(m_symbol,m_timeframe,shift);
           }

         if(foundHighTime!=0 && foundLowTime!=0 && prevHighTime!=0 && prevLowTime!=0)
            break;
        }

      if(foundHighTime!=0)
        {
         if(foundHighTime!=m_swingHighTime)
            m_prevSwingHigh=m_swingHigh;
         m_swingHigh=foundHigh;
         m_swingHighTime=foundHighTime;
         if(prevHighTime!=0)
            m_prevSwingHigh=prevHigh;
        }

      if(foundLowTime!=0)
        {
         if(foundLowTime!=m_swingLowTime)
            m_prevSwingLow=m_swingLow;
         m_swingLow=foundLow;
         m_swingLowTime=foundLowTime;
         if(prevLowTime!=0)
            m_prevSwingLow=prevLow;
        }
     }

   bool HasBullishHigherTimeframeBias(const ENUM_TIMEFRAMES tf) const
     {
      const int bars=iBars(m_symbol,tf);
      if(bars<5)
         return false;
      const double c1=iClose(m_symbol,tf,1);
      const double c2=iClose(m_symbol,tf,2);
      const double h1=iHigh(m_symbol,tf,1);
      const double h2=iHigh(m_symbol,tf,2);
      const double l1=iLow(m_symbol,tf,1);
      const double l2=iLow(m_symbol,tf,2);
      return (c1>=c2 && h1>=h2 && l1>=l2);
     }

   bool HasBearishHigherTimeframeBias(const ENUM_TIMEFRAMES tf) const
     {
      const int bars=iBars(m_symbol,tf);
      if(bars<5)
         return false;
      const double c1=iClose(m_symbol,tf,1);
      const double c2=iClose(m_symbol,tf,2);
      const double h1=iHigh(m_symbol,tf,1);
      const double h2=iHigh(m_symbol,tf,2);
      const double l1=iLow(m_symbol,tf,1);
      const double l2=iLow(m_symbol,tf,2);
      return (c1<=c2 && h1<=h2 && l1<=l2);
     }

   void RecalculateStructure()
     {
      m_boSStrong=false;
      const int bars=iBars(m_symbol,m_timeframe);
      if(bars<MathMax(10,m_lookback*2+3))
         return;

      const double close1=iClose(m_symbol,m_timeframe,1);
      const double close2=iClose(m_symbol,m_timeframe,2);
      const double high1=iHigh(m_symbol,m_timeframe,1);
      const double low1=iLow(m_symbol,m_timeframe,1);
      const double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      const double buffer=point*2.0;

      if(m_lastStructureHigh<=0.0 && m_swingHigh>0.0)
         m_lastStructureHigh=m_swingHigh;
      if(m_lastStructureLow<=0.0 && m_swingLow>0.0)
         m_lastStructureLow=m_swingLow;
      if(m_lastStructureHigh<=0.0 || m_lastStructureLow<=0.0)
         return;

      const bool bullishBreak=(close1>m_lastStructureHigh+buffer || high1>m_lastStructureHigh+buffer);
      const bool bearishBreak=(close1<m_lastStructureLow-buffer || low1<m_lastStructureLow-buffer);

      int bullishBars=0;
      int bearishBars=0;
      for(int i=1;i<=3 && i<bars;i++)
        {
         if(iClose(m_symbol,m_timeframe,i)>iOpen(m_symbol,m_timeframe,i)) bullishBars++;
         if(iClose(m_symbol,m_timeframe,i)<iOpen(m_symbol,m_timeframe,i)) bearishBars++;
        }
      m_boSStrong=(bullishBars>=2 || bearishBars>=2);

      if(bullishBreak)
        {
         const bool aligned=HasBullishHigherTimeframeBias(m_alignmentTf);
         if(aligned || m_state==STRUCTURE_BULLISH)
           {
            if(m_state!=STRUCTURE_BULLISH)
               PushEvent(EVENT_BULLISH_BOS);
            else
               PushEvent(EVENT_BULLISH_BOS);
            m_state=STRUCTURE_BULLISH;
           }
         else
           {
            PushEvent(EVENT_BULLISH_CHOCH);
            m_state=STRUCTURE_BULLISH;
           }
         m_lastStructureHigh=MathMax(m_lastStructureHigh,close1);
        }
      else if(bearishBreak)
        {
         const bool aligned=HasBearishHigherTimeframeBias(m_alignmentTf);
         if(aligned || m_state==STRUCTURE_BEARISH)
           {
            if(m_state!=STRUCTURE_BEARISH)
               PushEvent(EVENT_BEARISH_BOS);
            else
               PushEvent(EVENT_BEARISH_BOS);
            m_state=STRUCTURE_BEARISH;
           }
         else
           {
            PushEvent(EVENT_BEARISH_CHOCH);
            m_state=STRUCTURE_BEARISH;
           }
         m_lastStructureLow=MathMin(m_lastStructureLow,close1);
        }
      else
        {
         if(close1>m_lastStructureHigh && close2>m_lastStructureHigh)
            m_state=STRUCTURE_BULLISH;
         else if(close1<m_lastStructureLow && close2<m_lastStructureLow)
            m_state=STRUCTURE_BEARISH;
         else
            m_state=STRUCTURE_NEUTRAL;
        }
     }

public:
                     CMarketStructure()
        {
         m_symbol="";
         m_timeframe=PERIOD_CURRENT;
         m_alignmentTf=PERIOD_H1;
         m_lookback=5;
         m_scanDepth=120;
         m_state=STRUCTURE_NEUTRAL;
         m_lastEvent=EVENT_NONE;
         m_swingHigh=0.0;
         m_swingLow=0.0;
         m_swingHighTime=0;
         m_swingLowTime=0;
         m_prevSwingHigh=0.0;
         m_prevSwingLow=0.0;
         m_lastStructureHigh=0.0;
         m_lastStructureLow=0.0;
         m_boSStrong=false;
         m_eventIndex=0;
         m_lastBarTime=0;
         ArrayInitialize(m_eventBuffer,EVENT_NONE);
        }

   void Init(const ENUM_TIMEFRAMES timeframe,const string symbol,const int lookback=5,const ENUM_TIMEFRAMES alignmentTf=PERIOD_H1)
     {
      m_timeframe=timeframe;
      m_symbol=symbol;
      m_lookback=MathMax(2,lookback);
      m_alignmentTf=alignmentTf;
      m_scanDepth=MathMax(60,m_lookback*20);
     }

   void Refresh()
     {
      const datetime barTime=iTime(m_symbol,m_timeframe,0);
      if(barTime==0)
         return;
      if(barTime==m_lastBarTime && m_lastStructureHigh>0.0 && m_lastStructureLow>0.0)
         return;
      m_lastBarTime=barTime;
      UpdateRecentSwings();
      RecalculateStructure();
     }

   ENUM_STRUCTURE_STATE GetState() const { return m_state; }
   ENUM_STRUCTURE_EVENT GetLastEvent() const { return m_lastEvent; }
   double GetSwingHigh() const { return m_swingHigh; }
   double GetSwingLow() const { return m_swingLow; }
   double GetLastStructureHigh() const { return m_lastStructureHigh; }
   double GetLastStructureLow() const { return m_lastStructureLow; }
   datetime GetSwingHighTime() const { return m_swingHighTime; }
   datetime GetSwingLowTime() const { return m_swingLowTime; }
   bool IsBoSStrong() const { return m_boSStrong; }

   bool IsBullishOnHigher(const ENUM_TIMEFRAMES higherTf) const { return HasBullishHigherTimeframeBias(higherTf); }
   bool IsBearishOnHigher(const ENUM_TIMEFRAMES higherTf) const { return HasBearishHigherTimeframeBias(higherTf); }

   string StateToString() const
     {
      if(m_state==STRUCTURE_BULLISH) return "BULLISH";
      if(m_state==STRUCTURE_BEARISH) return "BEARISH";
      return "NEUTRAL";
     }

   string EventToString() const
     {
      if(m_lastEvent==EVENT_BULLISH_BOS) return "BULLISH BoS";
      if(m_lastEvent==EVENT_BEARISH_BOS) return "BEARISH BoS";
      if(m_lastEvent==EVENT_BULLISH_CHOCH) return "BULLISH ChoCh";
      if(m_lastEvent==EVENT_BEARISH_CHOCH) return "BEARISH ChoCh";
      if(m_lastEvent==EVENT_LIQUIDITY_POOL) return "LIQUIDITY";
      return "NONE";
     }

   void PrintStatus() const
     {
      Print("[ICT_MS] Symbol=",m_symbol," TF=",EnumToString(m_timeframe)," State=",StateToString()," Event=",EventToString()," SwingH=",DoubleToString(m_swingHigh,_Digits)," SwingL=",DoubleToString(m_swingLow,_Digits));
     }
  };

#endif
