/*
Project: ICT-MT5
Module: ICT_PDArray
Description: Builds the premium, discount, and OTE framework from the daily range, calculates Fibonacci confluence, and provides directional bias for the ICT EA.
Author: Malibongwe Ndhlovu
Supervisor: Malibongwe Ndhlovu
Date: 2026-05-18
Dependencies: ICT_MarketStructure.mqh and native MQL5 price series / symbol information functions.
*/
#ifndef ICT_PD_ARRAY_MQH
#define ICT_PD_ARRAY_MQH

#include <ICT_MarketStructure.mqh>

enum ENUM_ZONE_TYPE
  {
   ZONE_PREMIUM=0,
   ZONE_DISCOUNT=1,
   ZONE_MIDDLE=2,
   ZONE_OTE_BUY=3,
   ZONE_OTE_SELL=4,
   ZONE_EQWL=5
  };

enum ENUM_PD_STATE
  {
   PD_BULLISH=0,
   PD_BEARISH=1,
   PD_NEUTRAL=2
  };

struct SPDArrayZone
  {
   double          price;
   double          level;
   string          label;
   ENUM_ZONE_TYPE  type;
   double          fibRetrace;
   bool            isActive;
   double          confluence;
   int             toolsCount;
  };

struct SFibLevel
  {
   double price;
   double retrace;
   string label;
   bool   isKey;
  };

class CPDArray
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_dailyTf;
   int             m_lookback;
   SPDArrayZone    m_zones[];
   SFibLevel       m_fibLevels[];
   ENUM_PD_STATE   m_dailyBias;
   double          m_dailyHigh;
   double          m_dailyLow;
   double          m_dailyRange;
   double          m_fib50;
   double          m_oteZoneBuy;
   double          m_oteZoneSell;
   datetime        m_lastRefreshDay;

   void BuildFibLevels()
     {
      ArrayResize(m_fibLevels,8);
      const double fibs[8]={0.0,0.236,0.382,0.5,0.618,0.786,1.0,1.618};
      const string labels[8]={"0%","23.6%","38.2%","50%","61.8%","78.6%","100%","161.8%"};
      const bool keys[8]={false,false,true,true,true,true,false,true};
      for(int i=0;i<8;i++)
        {
         m_fibLevels[i].price=m_dailyLow+(m_dailyRange*fibs[i]);
         m_fibLevels[i].retrace=fibs[i];
         m_fibLevels[i].label=labels[i];
         m_fibLevels[i].isKey=keys[i];
        }
     }

   bool ValidDailyBars() const
     {
      return iBars(m_symbol,m_dailyTf)>=m_lookback+2;
     }

   void CalculateDailyFib()
     {
      if(!ValidDailyBars()) return;
      m_dailyHigh=iHigh(m_symbol,m_dailyTf,1);
      m_dailyLow=iLow(m_symbol,m_dailyTf,1);
      m_dailyRange=MathMax(_Point,MathAbs(m_dailyHigh-m_dailyLow));
      m_fib50=m_dailyLow+(m_dailyRange*0.5);
      m_oteZoneBuy=m_dailyHigh-(m_dailyRange*0.786);
      m_oteZoneSell=m_dailyLow+(m_dailyRange*0.786);
      BuildFibLevels();
     }

   ENUM_PD_STATE DetermineBias(const double bid) const
     {
      if(bid>m_fib50) return PD_BEARISH;
      if(bid<m_fib50) return PD_BULLISH;
      return PD_NEUTRAL;
     }

   int CalculateConfluence(const double price) const
     {
      int score=0;
      for(int i=0;i<ArraySize(m_fibLevels);i++)
        {
         if(!m_fibLevels[i].isKey) continue;
         const double dist=MathAbs(price-m_fibLevels[i].price);
         const double tolerance=MathMax(_Point*20.0,m_dailyRange*0.01);
         if(dist<=tolerance) score+=10;
         else if(dist<=tolerance*3.0) score+=5;
        }
      return MathMin(100,score);
     }

   ENUM_ZONE_TYPE ClassifyZone(const double retrace) const
     {
      if(retrace>=0.618 && retrace<=0.786) return ZONE_OTE_BUY;
      if(retrace>=0.214 && retrace<=0.382) return ZONE_OTE_SELL;
      if(retrace<0.5) return ZONE_DISCOUNT;
      if(retrace>0.5) return ZONE_PREMIUM;
      return ZONE_MIDDLE;
     }

public:
               CPDArray()
        {
         m_symbol="";
         m_dailyTf=PERIOD_D1;
         m_lookback=20;
         m_dailyBias=PD_NEUTRAL;
         m_dailyHigh=0.0;
         m_dailyLow=0.0;
         m_dailyRange=0.0;
         m_fib50=0.0;
         m_oteZoneBuy=0.0;
         m_oteZoneSell=0.0;
         m_lastRefreshDay=0;
        }

   void Init(const string symbol,const ENUM_TIMEFRAMES dailyTf=PERIOD_D1)
     {
      m_symbol=symbol;
      m_dailyTf=dailyTf;
      ArrayResize(m_zones,0);
     }

   void Refresh()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      const datetime today=(datetime)StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",dt.year,dt.mon,dt.day));
      if(today!=m_lastRefreshDay)
        {
         m_lastRefreshDay=today;
         CalculateDailyFib();
        }
      if(m_dailyRange<=0.0)
         CalculateDailyFib();
      const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      m_dailyBias=DetermineBias(bid);
      ArrayResize(m_zones,0);
      int zoneCount=0;
      for(int i=0;i<ArraySize(m_fibLevels);i++)
        {
         if(!m_fibLevels[i].isKey) continue;
         SPDArrayZone zone;
         zone.price=m_fibLevels[i].price;
         zone.level=m_fibLevels[i].price;
         zone.label=m_fibLevels[i].label;
         zone.fibRetrace=m_fibLevels[i].retrace;
         zone.type=ClassifyZone(m_fibLevels[i].retrace);
         zone.isActive=(MathAbs(bid-zone.price)<=MathMax(m_dailyRange*0.005,_Point*50.0));
         zone.confluence=CalculateConfluence(zone.price);
         zone.toolsCount=(zone.confluence>=20 ? 1 : 0);
         ArrayResize(m_zones,zoneCount+1);
         m_zones[zoneCount++]=zone;
        }
     }

   ENUM_PD_STATE GetDailyBias() const { return m_dailyBias; }
   bool IsInDiscountZone(const double price) const { return price<m_fib50; }
   bool IsInPremiumZone(const double price) const { return price>m_fib50; }

   bool IsInOTEBuyZone(const double price) const
     {
      const double lower=m_dailyHigh-(m_dailyRange*0.79);
      const double upper=m_dailyHigh-(m_dailyRange*0.618);
      return price>=lower && price<=upper;
     }

   bool IsInOTESellZone(const double price) const
     {
      const double lower=m_dailyLow+(m_dailyRange*0.618);
      const double upper=m_dailyLow+(m_dailyRange*0.79);
      return price>=lower && price<=upper;
     }

   bool GetNearestFibLevel(const double price,SFibLevel &level) const
     {
      double minDist=DBL_MAX;
      bool found=false;
      for(int i=0;i<ArraySize(m_fibLevels);i++)
        {
         const double dist=MathAbs(price-m_fibLevels[i].price);
         if(dist<minDist)
           {
            minDist=dist;
            level=m_fibLevels[i];
            found=true;
           }
        }
      return found;
     }

   void GetOTEBuyZone(double &lower,double &upper) const
     {
      lower=m_dailyHigh-(m_dailyRange*0.79);
      upper=m_dailyHigh-(m_dailyRange*0.618);
     }

   void GetOTESellZone(double &lower,double &upper) const
     {
      lower=m_dailyLow+(m_dailyRange*0.618);
      upper=m_dailyLow+(m_dailyRange*0.79);
     }

   double GetFib50() const { return m_fib50; }
   double GetDailyHigh() const { return m_dailyHigh; }
   double GetDailyLow() const { return m_dailyLow; }
   double GetDailyRange() const { return m_dailyRange; }
   int CountActiveZones() const
     {
      int count=0;
      for(int i=0;i<ArraySize(m_zones);i++) if(m_zones[i].isActive) count++;
      return count;
     }
  };

#endif
