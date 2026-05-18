/*
Project: ICT-MT5
Module: ICT_FairValueGap
Description: Detects three-candle fair value gaps, measures fill progress, and tracks whether gaps remain open, partially filled, filled, widened, or mitigated.
Author: Malibongwe Ndhlovu
Supervisor: Malibongwe Ndhlovu
Date: 2026-05-18
Dependencies: Native MQL5 price series functions (iBars, iHigh, iLow, iClose, iTime, SymbolInfoDouble, SymbolInfoInteger).
*/
#ifndef ICT_FAIR_VALUE_GAP_MQH
#define ICT_FAIR_VALUE_GAP_MQH

enum ENUM_FVG_TYPE
  {
   FVG_BULL=0,
   FVG_BEAR=1,
   FVG_NONE=2
  };

enum ENUM_FVG_STATE
  {
   FVG_OPEN=0,
   FVG_PARTIAL=1,
   FVG_FILLED=2,
   FVG_WIDENING=3,
   FVG_MITIGATED=4
  };

struct SFairValueGap
  {
   double          upper;
   double          lower;
   int             index;
   ENUM_FVG_TYPE   type;
   ENUM_FVG_STATE  state;
   double          fillRatio;
   datetime        time;
   double          size;
   bool            mitigated;
   bool            widened;
  };

class CFairValueGap
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   int               m_maxFVGs;
   SFairValueGap     m_bullFVGs[];
   SFairValueGap     m_bearFVGs[];
   datetime          m_lastBarTime;

   bool SeenBefore(const bool bullish,const double upper,const double lower) const
     {
      if(bullish)
        {
         for(int i=0;i<ArraySize(m_bullFVGs);i++)
            if(MathAbs(m_bullFVGs[i].upper-upper)<=_Point*2.0 && MathAbs(m_bullFVGs[i].lower-lower)<=_Point*2.0)
               return true;
        }
      else
        {
         for(int i=0;i<ArraySize(m_bearFVGs);i++)
            if(MathAbs(m_bearFVGs[i].upper-upper)<=_Point*2.0 && MathAbs(m_bearFVGs[i].lower-lower)<=_Point*2.0)
               return true;
        }
      return false;
     }

   double SymbolMinGap() const
     {
      const double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      const int digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      if(StringFind(m_symbol,"XAU")>=0) return 30.0*point;
      if(StringFind(m_symbol,"NAS")>=0 || StringFind(m_symbol,"US")>=0) return 20.0*point;
      return (digits==3 || digits==5) ? 10.0*point : 5.0*point;
     }

   void Trim(SFairValueGap &arr[])
     {
      while(ArraySize(arr)>m_maxFVGs)
        {
         for(int i=0;i<ArraySize(arr)-1;i++)
            arr[i]=arr[i+1];
         ArrayResize(arr,ArraySize(arr)-1);
        }
     }

   bool DetectAt(const int midIndex,const bool bullish)
     {
      const int bars=iBars(m_symbol,m_timeframe);
      if(midIndex<1 || midIndex+1>=bars)
         return false;

      const int left=midIndex+1;
      const int right=midIndex-1;
      const double leftHigh=iHigh(m_symbol,m_timeframe,left);
      const double leftLow=iLow(m_symbol,m_timeframe,left);
      const double rightHigh=iHigh(m_symbol,m_timeframe,right);
      const double rightLow=iLow(m_symbol,m_timeframe,right);

      SFairValueGap fvg;
      fvg.index=midIndex;
      fvg.time=iTime(m_symbol,m_timeframe,midIndex);
      fvg.fillRatio=0.0;
      fvg.state=FVG_OPEN;
      fvg.mitigated=false;
      fvg.widened=false;

      if(bullish)
        {
         if(rightLow<=leftHigh)
            return false;
         fvg.upper=rightLow;
         fvg.lower=leftHigh;
         fvg.type=FVG_BULL;
        }
      else
        {
         if(rightHigh>=leftLow)
            return false;
         fvg.upper=leftLow;
         fvg.lower=rightHigh;
         fvg.type=FVG_BEAR;
        }

      fvg.size=MathAbs(fvg.upper-fvg.lower);
      if(fvg.size<SymbolMinGap())
         return false;
      if(SeenBefore(bullish,fvg.upper,fvg.lower))
         return false;

      if(bullish)
        {
         const int size=ArraySize(m_bullFVGs);
         ArrayResize(m_bullFVGs,size+1);
         m_bullFVGs[size]=fvg;
         Trim(m_bullFVGs);
        }
      else
        {
         const int size=ArraySize(m_bearFVGs);
         ArrayResize(m_bearFVGs,size+1);
         m_bearFVGs[size]=fvg;
         Trim(m_bearFVGs);
        }
      return true;
     }

   void UpdateArray(SFairValueGap &arr[],const double price)
     {
      for(int i=0;i<ArraySize(arr);i++)
        {
         SFairValueGap &fvg=arr[i];
         if(fvg.state==FVG_FILLED || fvg.state==FVG_MITIGATED)
            continue;

         if(price>fvg.upper)
           {
            fvg.widened=true;
            fvg.state=FVG_WIDENING;
           }

         const double span=MathAbs(fvg.upper-fvg.lower);
         if(span<=0.0)
            continue;

         if(price>=fvg.lower && price<=fvg.upper)
           {
            if(fvg.type==FVG_BULL)
              {
               const double filled=fvg.upper-price;
               fvg.fillRatio=MathMax(fvg.fillRatio,MathMax(0.0,MathMin(1.0,filled/span)));
              }
            else
              {
               const double filled=price-fvg.lower;
               fvg.fillRatio=MathMax(fvg.fillRatio,MathMax(0.0,MathMin(1.0,filled/span)));
              }
            fvg.state=(fvg.fillRatio>=0.999 ? FVG_FILLED : FVG_PARTIAL);
           }
         else if((fvg.type==FVG_BULL && price<=fvg.lower) || (fvg.type==FVG_BEAR && price>=fvg.upper))
           {
            fvg.fillRatio=1.0;
            fvg.state=FVG_MITIGATED;
            fvg.mitigated=true;
           }
        }
     }

public:
               CFairValueGap()
        {
         m_symbol="";
         m_timeframe=PERIOD_CURRENT;
         m_maxFVGs=15;
         m_lastBarTime=0;
        }

   void Init(const string symbol,const ENUM_TIMEFRAMES timeframe)
     {
      m_symbol=symbol;
      m_timeframe=timeframe;
      ArrayResize(m_bullFVGs,0);
      ArrayResize(m_bearFVGs,0);
     }

   void Refresh(const int lookback=30)
     {
      const datetime barTime=iTime(m_symbol,m_timeframe,0);
      if(barTime==0) return;
      const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      if(barTime!=m_lastBarTime)
        {
         m_lastBarTime=barTime;
         const int bars=iBars(m_symbol,m_timeframe);
         const int limit=MathMin(lookback,bars-3);
         for(int i=1;i<=limit;i++)
           {
            DetectAt(i,true);
            DetectAt(i,false);
           }
        }
      UpdateArray(m_bullFVGs,bid);
      UpdateArray(m_bearFVGs,bid);
     }

   bool GetNearestOpenBullishFVG(const double price,SFairValueGap &fvg) const
     {
      double bestDist=DBL_MAX;
      bool found=false;
      for(int i=0;i<ArraySize(m_bullFVGs);i++)
        {
         const SFairValueGap &candidate=m_bullFVGs[i];
         if(candidate.state==FVG_FILLED || candidate.state==FVG_MITIGATED)
            continue;
         if(candidate.upper>=price)
            continue;
         const double dist=price-candidate.upper;
         if(dist<bestDist)
           {
            bestDist=dist;
            fvg=candidate;
            found=true;
           }
        }
      return found;
     }

   bool GetNearestOpenBearishFVG(const double price,SFairValueGap &fvg) const
     {
      double bestDist=DBL_MAX;
      bool found=false;
      for(int i=0;i<ArraySize(m_bearFVGs);i++)
        {
         const SFairValueGap &candidate=m_bearFVGs[i];
         if(candidate.state==FVG_FILLED || candidate.state==FVG_MITIGATED)
            continue;
         if(candidate.lower<=price)
            continue;
         const double dist=candidate.lower-price;
         if(dist<bestDist)
           {
            bestDist=dist;
            fvg=candidate;
            found=true;
           }
        }
      return found;
     }

   bool IsPriceInBullishFVG(const double price) const
     {
      for(int i=0;i<ArraySize(m_bullFVGs);i++)
         if(m_bullFVGs[i].state!=FVG_FILLED && m_bullFVGs[i].state!=FVG_MITIGATED && price>=m_bullFVGs[i].lower && price<=m_bullFVGs[i].upper)
            return true;
      return false;
     }

   bool IsPriceInBearishFVG(const double price) const
     {
      for(int i=0;i<ArraySize(m_bearFVGs);i++)
         if(m_bearFVGs[i].state!=FVG_FILLED && m_bearFVGs[i].state!=FVG_MITIGATED && price>=m_bearFVGs[i].lower && price<=m_bearFVGs[i].upper)
            return true;
      return false;
     }

   int GetFVGConfidence(const ENUM_FVG_TYPE ftype) const
     {
      const int count=(ftype==FVG_BULL ? ArraySize(m_bullFVGs) : ArraySize(m_bearFVGs));
      if(count==0)
         return 0;
      int score=20;
      int openCount=0;
      int mitigatedCount=0;
      double avgSize=0.0;
      if(ftype==FVG_BULL)
        {
         for(int i=0;i<ArraySize(m_bullFVGs);i++)
           {
            if(m_bullFVGs[i].state==FVG_OPEN) openCount++;
            if(m_bullFVGs[i].state==FVG_MITIGATED) mitigatedCount++;
            avgSize+=m_bullFVGs[i].size;
           }
        }
      else
        {
         for(int i=0;i<ArraySize(m_bearFVGs);i++)
           {
            if(m_bearFVGs[i].state==FVG_OPEN) openCount++;
            if(m_bearFVGs[i].state==FVG_MITIGATED) mitigatedCount++;
            avgSize+=m_bearFVGs[i].size;
           }
        }
      avgSize/=count;
      score+=openCount*10;
      score+=MathMax(0,10-mitigatedCount*2);
      score+=((avgSize>=SymbolMinGap()*2.0) ? 15 : 5);
      return MathMin(100,score);
     }

   int CountOpenBullishFVGs() const
     {
      int c=0;
      for(int i=0;i<ArraySize(m_bullFVGs);i++)
         if(m_bullFVGs[i].state==FVG_OPEN || m_bullFVGs[i].state==FVG_PARTIAL || m_bullFVGs[i].state==FVG_WIDENING) c++;
      return c;
     }

   int CountOpenBearishFVGs() const
     {
      int c=0;
      for(int i=0;i<ArraySize(m_bearFVGs);i++)
         if(m_bearFVGs[i].state==FVG_OPEN || m_bearFVGs[i].state==FVG_PARTIAL || m_bearFVGs[i].state==FVG_WIDENING) c++;
      return c;
     }
  };

#endif
