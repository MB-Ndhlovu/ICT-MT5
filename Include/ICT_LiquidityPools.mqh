#ifndef ICT_LIQUIDITY_POOLS_MQH
#define ICT_LIQUIDITY_POOLS_MQH

enum ENUM_LIQ_TYPE
  {
   LIQ_BSL=0,
   LIQ_SSL=1,
   LIQ_EQH=2,
   LIQ_EQL=3
  };

enum ENUM_SWEEP_STATE
  {
   SWEEP_NONE=0,
   SWEEP_DETECTED=1,
   SWEEP_CONFIRMED=2
  };

struct SLiquidityPool
  {
   double         price;
   ENUM_LIQ_TYPE  type;
   int            strength;
   int            barIndex;
   datetime       time;
   int            touches;
   bool           isSwept;
   double         sweepVolume;
   ENUM_SWEEP_STATE state;
   bool           mitigated;
  };

class CLiquidityPools
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_maxPools;
   int             m_lookback;
   double          m_tolerancePoints;
   SLiquidityPool  m_pools[];
   datetime        m_lastBarTime;

   bool IsSwingHigh(const int index,const int lookback) const
     {
      const int bars=iBars(m_symbol,m_timeframe);
      if(index<lookback || index>=bars-lookback) return false;
      const double high=iHigh(m_symbol,m_timeframe,index);
      for(int i=1;i<=lookback;i++)
         if(iHigh(m_symbol,m_timeframe,index-i)>=high || iHigh(m_symbol,m_timeframe,index+i)>=high)
            return false;
      return true;
     }

   bool IsSwingLow(const int index,const int lookback) const
     {
      const int bars=iBars(m_symbol,m_timeframe);
      if(index<lookback || index>=bars-lookback) return false;
      const double low=iLow(m_symbol,m_timeframe,index);
      for(int i=1;i<=lookback;i++)
         if(iLow(m_symbol,m_timeframe,index-i)<=low || iLow(m_symbol,m_timeframe,index+i)<=low)
            return false;
      return true;
     }

   bool IsEqualHigh(const int index,const int lookback,const double tolerance) const
     {
      const double high=iHigh(m_symbol,m_timeframe,index);
      for(int i=index-1;i>=MathMax(0,index-lookback);i--)
         if(MathAbs(high-iHigh(m_symbol,m_timeframe,i))<=tolerance)
            return true;
      return false;
     }

   bool IsEqualLow(const int index,const int lookback,const double tolerance) const
     {
      const double low=iLow(m_symbol,m_timeframe,index);
      for(int i=index-1;i>=MathMax(0,index-lookback);i--)
         if(MathAbs(low-iLow(m_symbol,m_timeframe,i))<=tolerance)
            return true;
      return false;
     }

   int FindPoolIndex(const double price,const ENUM_LIQ_TYPE type) const
     {
      for(int i=0;i<ArraySize(m_pools);i++)
         if(m_pools[i].type==type && MathAbs(m_pools[i].price-price)<=m_tolerancePoints*_Point)
            return i;
      return -1;
     }

   void AddOrUpdatePool(const double price,const ENUM_LIQ_TYPE type,const int barIndex)
     {
      const int idx=FindPoolIndex(price,type);
      if(idx>=0)
        {
         m_pools[idx].touches++;
         m_pools[idx].strength=MathMin(10,m_pools[idx].strength+1);
         return;
        }

      SLiquidityPool pool;
      pool.price=price;
      pool.type=type;
      pool.strength=5;
      pool.barIndex=barIndex;
      pool.time=iTime(m_symbol,m_timeframe,barIndex);
      pool.touches=1;
      pool.isSwept=false;
      pool.sweepVolume=0.0;
      pool.state=SWEEP_NONE;
      pool.mitigated=false;
      const int size=ArraySize(m_pools);
      ArrayResize(m_pools,size+1);
      m_pools[size]=pool;
      while(ArraySize(m_pools)>m_maxPools)
        {
         for(int i=0;i<ArraySize(m_pools)-1;i++) m_pools[i]=m_pools[i+1];
         ArrayResize(m_pools,ArraySize(m_pools)-1);
        }
     }

   ENUM_SWEEP_STATE DetectSweepForPool(const SLiquidityPool &pool,const double bid,const double closePrice) const
     {
      const double sweepAllowance=MathMax(_Point*m_tolerancePoints,MathAbs(pool.price)*0.0001);
      if((pool.type==LIQ_BSL || pool.type==LIQ_EQH) && bid>pool.price+sweepAllowance && closePrice<pool.price)
         return SWEEP_CONFIRMED;
      if((pool.type==LIQ_SSL || pool.type==LIQ_EQL) && bid<pool.price-sweepAllowance && closePrice>pool.price)
         return SWEEP_CONFIRMED;
      if((pool.type==LIQ_BSL || pool.type==LIQ_EQH) && bid>pool.price+sweepAllowance*0.5)
         return SWEEP_DETECTED;
      if((pool.type==LIQ_SSL || pool.type==LIQ_EQL) && bid<pool.price-sweepAllowance*0.5)
         return SWEEP_DETECTED;
      return SWEEP_NONE;
     }

   void UpdatePools()
     {
      const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      const double closePrice=iClose(m_symbol,m_timeframe,1);
      for(int i=0;i<ArraySize(m_pools);i++)
        {
         SLiquidityPool &pool=m_pools[i];
         if(pool.isSwept)
           {
            if(MathAbs(closePrice-pool.price)<=_Point*m_tolerancePoints)
               pool.mitigated=true;
            continue;
           }

         const ENUM_SWEEP_STATE sweep=DetectSweepForPool(pool,bid,closePrice);
         if(sweep==SWEEP_CONFIRMED)
           {
            pool.state=SWEEP_CONFIRMED;
            pool.isSwept=true;
            pool.sweepVolume=iVolume(m_symbol,m_timeframe,1);
           }
         else if(sweep==SWEEP_DETECTED)
           {
            pool.state=SWEEP_DETECTED;
           }
        }
     }

public:
               CLiquidityPools()
        {
         m_symbol="";
         m_timeframe=PERIOD_CURRENT;
         m_maxPools=20;
         m_lookback=5;
         m_tolerancePoints=20.0;
         m_lastBarTime=0;
         ArrayResize(m_pools,0);
        }

   void Init(const string symbol,const ENUM_TIMEFRAMES timeframe,const int lookback=5)
     {
      m_symbol=symbol;
      m_timeframe=timeframe;
      m_lookback=MathMax(2,lookback);
      ArrayResize(m_pools,0);
     }

   void Refresh()
     {
      const datetime barTime=iTime(m_symbol,m_timeframe,0);
      if(barTime==0) return;
      if(barTime!=m_lastBarTime)
        {
         m_lastBarTime=barTime;
         const int bars=iBars(m_symbol,m_timeframe);
         const int limit=MathMin(bars-m_lookback-1,m_lookback*8);
         for(int i=m_lookback;i<=limit;i++)
           {
            const double tol=MathMax(_Point*10.0,SymbolInfoDouble(m_symbol,SYMBOL_POINT)*20.0);
            if(IsSwingHigh(i,m_lookback))
              {
               const double price=iHigh(m_symbol,m_timeframe,i);
               AddOrUpdatePool(price,IsEqualHigh(i,m_lookback*2,tol) ? LIQ_EQH : LIQ_BSL,i);
              }
            if(IsSwingLow(i,m_lookback))
              {
               const double price=iLow(m_symbol,m_timeframe,i);
               AddOrUpdatePool(price,IsEqualLow(i,m_lookback*2,tol) ? LIQ_EQL : LIQ_SSL,i);
              }
           }
        }
      UpdatePools();
     }

   bool GetNearestBSL(const double price,SLiquidityPool &pool) const
     {
      double bestDist=DBL_MAX;
      bool found=false;
      for(int i=0;i<ArraySize(m_pools);i++)
        {
         const SLiquidityPool &candidate=m_pools[i];
         if(candidate.isSwept) continue;
         if(candidate.type!=LIQ_BSL && candidate.type!=LIQ_EQH) continue;
         if(candidate.price<price) continue;
         const double dist=candidate.price-price;
         if(dist<bestDist)
           {
            bestDist=dist;
            pool=candidate;
            found=true;
           }
        }
      return found;
     }

   bool GetNearestSSL(const double price,SLiquidityPool &pool) const
     {
      double bestDist=DBL_MAX;
      bool found=false;
      for(int i=0;i<ArraySize(m_pools);i++)
        {
         const SLiquidityPool &candidate=m_pools[i];
         if(candidate.isSwept) continue;
         if(candidate.type!=LIQ_SSL && candidate.type!=LIQ_EQL) continue;
         if(candidate.price>price) continue;
         const double dist=price-candidate.price;
         if(dist<bestDist)
           {
            bestDist=dist;
            pool=candidate;
            found=true;
           }
        }
      return found;
     }

   ENUM_SWEEP_STATE WasLiquiditySwept() const
     {
      for(int i=0;i<ArraySize(m_pools);i++)
         if(m_pools[i].state==SWEEP_CONFIRMED)
            return SWEEP_CONFIRMED;
      return SWEEP_NONE;
     }

   int GetPoolStrength(const double price,const bool isBullishSetup) const
     {
      int strength=0;
      for(int i=0;i<ArraySize(m_pools);i++)
        {
         const double dist=MathAbs(price-m_pools[i].price);
         const double threshold=MathMax(_Point*m_tolerancePoints*2.5,_Point*50.0);
         if(dist>threshold) continue;
         if(isBullishSetup && (m_pools[i].type==LIQ_SSL || m_pools[i].type==LIQ_EQL))
            strength+=m_pools[i].strength;
         if(!isBullishSetup && (m_pools[i].type==LIQ_BSL || m_pools[i].type==LIQ_EQH))
            strength+=m_pools[i].strength;
        }
      return MathMin(30,strength);
     }

   int CountSweptPools() const
     {
      int count=0;
      for(int i=0;i<ArraySize(m_pools);i++) if(m_pools[i].isSwept) count++;
      return count;
     }
  };

#endif
