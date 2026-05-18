#ifndef ICT_ORDER_BLOCKS_MQH
#define ICT_ORDER_BLOCKS_MQH

#include <ICT_MarketStructure.mqh>

enum ENUM_OB_TYPE
  {
   OB_BULL=0,
   OB_BEAR=1
  };

enum ENUM_OB_STATE
  {
   OB_PENDING=0,
   OB_ACTIVE=1,
   OB_WEAKENING=2,
   OB_BROKEN=3
  };

struct SOrderBlock
  {
   double          upper;
   double          lower;
   int             triggerBar;
   ENUM_OB_TYPE    type;
   ENUM_OB_STATE   state;
   double          volume;
   datetime        time;
   double          efficiency;
   bool            mitigated;
   int             mitigationTouches;
  };

class COrderBlocks
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_maxOBs;
   int               m_lookback;
   SOrderBlock      m_obBulls[];
   SOrderBlock      m_obBears[];
   CMarketStructure *m_struct;
   datetime         m_lastBarTime;

   bool IsBullishBar(const int index) const
     {
      return iClose(m_symbol,m_timeframe,index)>iOpen(m_symbol,m_timeframe,index);
     }

   bool IsBearishBar(const int index) const
     {
      return iClose(m_symbol,m_timeframe,index)<iOpen(m_symbol,m_timeframe,index);
     }

   double BarRange(const int index) const
     {
      return iHigh(m_symbol,m_timeframe,index)-iLow(m_symbol,m_timeframe,index);
     }

   double BarVolume(const int index) const
     {
      return (double)iVolume(m_symbol,m_timeframe,index);
     }

   double Efficiency(const int index) const
     {
      const double range=BarRange(index);
      if(range<=0.0) return 0.0;
      const double body=MathAbs(iClose(m_symbol,m_timeframe,index)-iOpen(m_symbol,m_timeframe,index));
      return MathMax(0.0,MathMin(1.0,body/range));
     }

   bool AlreadyTrackedBullish(const double upper,const double lower) const
     {
      for(int i=0;i<ArraySize(m_obBulls);i++)
        {
         if(MathAbs(m_obBulls[i].upper-upper)<=_Point*10.0 && MathAbs(m_obBulls[i].lower-lower)<=_Point*10.0)
            return true;
        }
      return false;
     }

   bool AlreadyTrackedBearish(const double upper,const double lower) const
     {
      for(int i=0;i<ArraySize(m_obBears);i++)
        {
         if(MathAbs(m_obBears[i].upper-upper)<=_Point*10.0 && MathAbs(m_obBears[i].lower-lower)<=_Point*10.0)
            return true;
        }
      return false;
     }

   void TrimBullish()
     {
      while(ArraySize(m_obBulls)>m_maxOBs)
        {
         for(int i=0;i<ArraySize(m_obBulls)-1;i++)
            m_obBulls[i]=m_obBulls[i+1];
         ArrayResize(m_obBulls,ArraySize(m_obBulls)-1);
        }
     }

   void TrimBearish()
     {
      while(ArraySize(m_obBears)>m_maxOBs)
        {
         for(int i=0;i<ArraySize(m_obBears)-1;i++)
            m_obBears[i]=m_obBears[i+1];
         ArrayResize(m_obBears,ArraySize(m_obBears)-1);
        }
     }

   bool CreateOB(const int triggerBar,const bool bullish)
     {
      if(triggerBar<2) return false;
      if(bullish && !IsBearishBar(triggerBar)) return false;
      if(!bullish && !IsBullishBar(triggerBar)) return false;

      const int bars=iBars(m_symbol,m_timeframe);
      if(triggerBar+3>=bars) return false;

      int impulseCount=0;
      double impulseVolume=0.0;
      for(int i=triggerBar-1;i>=1 && i>=triggerBar-3;i--)
        {
         if(bullish ? IsBullishBar(i) : IsBearishBar(i))
           {
            impulseCount++;
            impulseVolume+=BarVolume(i);
           }
        }
      if(impulseCount<2) return false;

      SOrderBlock ob;
      ob.upper=iHigh(m_symbol,m_timeframe,triggerBar);
      ob.lower=iLow(m_symbol,m_timeframe,triggerBar);
      ob.triggerBar=triggerBar;
      ob.type=bullish ? OB_BULL : OB_BEAR;
      ob.state=OB_PENDING;
      ob.volume=(impulseCount>0 ? impulseVolume/impulseCount : 0.0);
      ob.time=iTime(m_symbol,m_timeframe,triggerBar);
      ob.efficiency=Efficiency(triggerBar);
      ob.mitigated=false;
      ob.mitigationTouches=0;

      if(bullish)
        {
         if(AlreadyTrackedBullish(ob.upper,ob.lower)) return false;
         const int size=ArraySize(m_obBulls);
         ArrayResize(m_obBulls,size+1);
         m_obBulls[size]=ob;
         TrimBullish();
        }
      else
        {
         if(AlreadyTrackedBearish(ob.upper,ob.lower)) return false;
         const int size=ArraySize(m_obBears);
         ArrayResize(m_obBears,size+1);
         m_obBears[size]=ob;
         TrimBearish();
        }
      return true;
     }

   void UpdateStates()
     {
      const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      const double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      const double price=(bid+ask)*0.5;

      for(int i=0;i<ArraySize(m_obBulls);i++)
        {
         SOrderBlock &ob=m_obBulls[i];
         if(ob.state==OB_BROKEN) continue;
         if(price>=ob.lower && price<=ob.upper)
           {
            ob.state=OB_ACTIVE;
            ob.mitigationTouches++;
            if(price<=ob.lower+(_Point*10.0)) ob.mitigated=true;
           }
         else if(price<ob.lower)
           {
            ob.state=OB_WEAKENING;
            if(price<ob.lower-(_Point*20.0)) ob.state=OB_BROKEN;
           }
         else if(price>ob.upper)
           {
            ob.state=OB_BROKEN;
           }
        }

      for(int i=0;i<ArraySize(m_obBears);i++)
        {
         SOrderBlock &ob=m_obBears[i];
         if(ob.state==OB_BROKEN) continue;
         if(price>=ob.lower && price<=ob.upper)
           {
            ob.state=OB_ACTIVE;
            ob.mitigationTouches++;
            if(price>=ob.upper-(_Point*10.0)) ob.mitigated=true;
           }
         else if(price>ob.upper)
           {
            ob.state=OB_WEAKENING;
            if(price>ob.upper+(_Point*20.0)) ob.state=OB_BROKEN;
           }
         else if(price<ob.lower)
           {
            ob.state=OB_BROKEN;
           }
        }
     }

public:
               COrderBlocks()
        {
         m_symbol="";
         m_timeframe=PERIOD_CURRENT;
         m_maxOBs=10;
         m_lookback=20;
         m_struct=NULL;
         m_lastBarTime=0;
        }

   void Init(const string symbol,const ENUM_TIMEFRAMES timeframe,CMarketStructure *structRef)
     {
      m_symbol=symbol;
      m_timeframe=timeframe;
      m_struct=structRef;
      ArrayResize(m_obBulls,0);
      ArrayResize(m_obBears,0);
     }

   void Refresh(const int lookback=20)
     {
      m_lookback=MathMax(lookback,5);
      const datetime barTime=iTime(m_symbol,m_timeframe,0);
      if(barTime==0)
         return;
      if(barTime!=m_lastBarTime)
        {
         m_lastBarTime=barTime;
         const int bars=iBars(m_symbol,m_timeframe);
         const int limit=MathMin(bars-4,m_lookback);
         for(int i=2;i<=limit;i++)
           {
            const bool bullishBreak=(iClose(m_symbol,m_timeframe,i-1)>iHigh(m_symbol,m_timeframe,i)+_Point*2.0 || (m_struct!=NULL && (m_struct->GetLastEvent()==EVENT_BULLISH_BOS || m_struct->GetLastEvent()==EVENT_BULLISH_CHOCH)));
            const bool bearishBreak=(iClose(m_symbol,m_timeframe,i-1)<iLow(m_symbol,m_timeframe,i)-_Point*2.0 || (m_struct!=NULL && (m_struct->GetLastEvent()==EVENT_BEARISH_BOS || m_struct->GetLastEvent()==EVENT_BEARISH_CHOCH)));
            if(bullishBreak) CreateOB(i,true);
            if(bearishBreak) CreateOB(i,false);
           }
        }
      UpdateStates();
     }

   bool GetNearestBullishOB(const double price,SOrderBlock &ob) const
     {
      double bestDist=DBL_MAX;
      bool found=false;
      for(int i=0;i<ArraySize(m_obBulls);i++)
        {
         const SOrderBlock &candidate=m_obBulls[i];
         if(candidate.state==OB_BROKEN) continue;
         if(price<candidate.lower) continue;
         const double dist=MathAbs(price-candidate.lower);
         if(dist<bestDist)
           {
            bestDist=dist;
            ob=candidate;
            found=true;
           }
        }
      return found;
     }

   bool GetNearestBearishOB(const double price,SOrderBlock &ob) const
     {
      double bestDist=DBL_MAX;
      bool found=false;
      for(int i=0;i<ArraySize(m_obBears);i++)
        {
         const SOrderBlock &candidate=m_obBears[i];
         if(candidate.state==OB_BROKEN) continue;
         if(price>candidate.upper) continue;
         const double dist=MathAbs(candidate.upper-price);
         if(dist<bestDist)
           {
            bestDist=dist;
            ob=candidate;
            found=true;
           }
        }
      return found;
     }

   bool IsPriceInBullishOBZone(const double price) const
     {
      for(int i=0;i<ArraySize(m_obBulls);i++)
         if(m_obBulls[i].state!=OB_BROKEN && price>=m_obBulls[i].lower && price<=m_obBulls[i].upper)
            return true;
      return false;
     }

   bool IsPriceInBearishOBZone(const double price) const
     {
      for(int i=0;i<ArraySize(m_obBears);i++)
         if(m_obBears[i].state!=OB_BROKEN && price>=m_obBears[i].lower && price<=m_obBears[i].upper)
            return true;
      return false;
     }

   int CountActiveBullishOBs() const
     {
      int count=0;
      for(int i=0;i<ArraySize(m_obBulls);i++)
         if(m_obBulls[i].state==OB_ACTIVE) count++;
      return count;
     }

   int CountActiveBearishOBs() const
     {
      int count=0;
      for(int i=0;i<ArraySize(m_obBears);i++)
         if(m_obBears[i].state==OB_ACTIVE) count++;
      return count;
     }

   int CountMitigatedBullishOBs() const
     {
      int count=0;
      for(int i=0;i<ArraySize(m_obBulls);i++)
         if(m_obBulls[i].mitigated) count++;
      return count;
     }

   int CountMitigatedBearishOBs() const
     {
      int count=0;
      for(int i=0;i<ArraySize(m_obBears);i++)
         if(m_obBears[i].mitigated) count++;
      return count;
     }
  };

#endif
