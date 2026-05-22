/*
Project: ICT-MT5
Module: ICT_RiskManager
Description: Manages pip sizing, lot sizing, daily loss caps, drawdown state, and trade history.
              ATR-adaptive stop loss for XAUUSD. Fixed stops for NAS100/US30 indices.
Author: Malibongwe Ndhlovu
Supervisor: Malibongwe Ndhlovu
Date: 2026-05-23
Changes:
  - v1.02: ATR-adaptive stops — XAUUSD uses 0.5x ATR(H1), NAS100/US30 use fixed stops.
           Stop = ATR * multiplier. TP = Stop * RR_ratio. Both scale with volatility.
Dependencies: Native MQL5 account, symbol, and trade history functions.
*/
#ifndef ICT_RISK_MANAGER_MQH
#define ICT_RISK_MANAGER_MQH

enum ENUM_RISK_STATE
  {
   RISK_OK=0,
   RISK_WARNING=1,
   RISK_HALTED=2,
   RISK_DAILY_RESET=3
  };

struct STradeRecord
  {
   double    entryPrice;
   double    exitPrice;
   double    stopLoss;
   double    takeProfit;
   double    lotSize;
   double    riskAmount;
   double    pnl;
   bool      isWin;
   bool      isBuy;
   datetime  openTime;
   datetime  closeTime;
   string    symbol;
  };

class CRiskManager
  {
private:
   string         m_symbol;
   double         m_riskPercent;
   double         m_maxDailyLoss;
   double         m_dailyLossCap;
   double         m_accountEquity;
   double         m_dailyPnL;
   double         m_sessionPnL;
   int            m_consecutiveLosses;
   int            m_maxConsecutiveLosses;
   datetime       m_lastResetDate;
   STradeRecord   m_tradeHistory[];
   ENUM_RISK_STATE m_state;
   double         m_pipValue;
   datetime       m_lastRefreshTime;

   // --- ATR-adaptive stop configuration ---
   double         m_atrMultiplier;     // multiplier for ATR stop (0.5 for XAUUSD)
   double         m_rrRatio;            // risk:reward ratio (default 3.0)
   double         m_atrValue;           // current ATR value in price units
   int            m_stopLossPips;       // computed stop loss in pips
   int            m_takeProfitPips;     // computed take profit in pips

   double PipSize(const string symbol) const
     {
      const double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      const int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      if(StringFind(symbol,\"XAU\")>=0)
         return MathMax(point*10.0,0.1);
      if(StringFind(symbol,\"NAS\")>=0 || StringFind(symbol,\"US30\")>=0 || StringFind(symbol,\"US 30\")>=0 || StringFind(symbol,\"DJ\")>=0 || StringFind(symbol,\"USTEC\")>=0)
         return MathMax(point,1.0);
      return ((digits==3 || digits==5) ? point*10.0 : point);
     }

   double PipValuePerLot(const string symbol) const
     {
      const double pipSize=PipSize(symbol);
      const double tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      const double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickValue>0.0 && tickSize>0.0)
         return tickValue*(pipSize/tickSize);
      const double contractSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      if(contractSize>0.0)
         return contractSize*pipSize;
      if(StringFind(symbol,\"XAU\")>=0)
         return 10.0;
      if(StringFind(symbol,\"NAS\")>=0 || StringFind(symbol,\"US30\")>=0 || StringFind(symbol,\"US 30\")>=0 || StringFind(symbol,\"DJ\")>=0 || StringFind(symbol,\"USTEC\")>=0)
         return 1.0;
      return 1.0;
     }

   void ResetIfNewDay()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      const datetime today=(datetime)StringToTime(StringFormat(\"%04d.%02d.%02d 00:00:00\",dt.year,dt.mon,dt.day));
      if(today!=m_lastResetDate)
        {
         m_lastResetDate=today;
         m_dailyPnL=0.0;
         m_sessionPnL=0.0;
         m_consecutiveLosses=0;
         m_state=RISK_OK;
        }
     }

   double RawRiskAmount() const
     {
      return m_accountEquity*(m_riskPercent/100.0);
     }

   double NormalizeVolume(const string symbol,const double lots) const
     {
      const double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      const double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      const double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0) return MathMax(minLot,MathMin(maxLot,lots));
      double normalized=MathFloor(lots/step)*step;
      normalized=NormalizeDouble(normalized,2);
      if(normalized<minLot) normalized=minLot;
      if(normalized>maxLot) normalized=maxLot;
      return normalized;
     }

   // =====================================================================
   // ATR CALCULATION — iATR on the exec timeframe bars
   // =====================================================================
   double CalcATR(const string symbol,const ENUM_TIMEFRAMES tf,const int period=14) const
     {
      int handle=iATR(symbol,tf,period);
      if(handle==INVALID_HANDLE)
         return 0.0;
      double buf[];
      if(CopyBuffer(handle,0,0,1,buf)!=-1)
        {
         double val=buf[0];
         IndicatorRelease(handle);
         return val;
        }
      IndicatorRelease(handle);
      return 0.0;
     }

   // =====================================================================
   // ATR-ADAPTIVE STOPLOSS — key optimization from stress test
   // XAUUSD: SL = 0.5x ATR(H1)  |  TP = SL * 3.0  (true 1:3)
   // NAS100/US30: fixed stop (indices move in points, not pips)
   // =====================================================================
   void ComputeATRStops()
     {
      m_atrValue=0.0;
      m_stopLossPips=0;
      m_takeProfitPips=0;

      // Use M5 for exec (faster signal) but ATR on H1 (more stable)
      const ENUM_TIMEFRAMES atrTf=(StringFind(m_symbol,\"XAU\")>=0) ? PERIOD_H1 : PERIOD_M5;
      m_atrValue=CalcATR(m_symbol,atrTf,14);

      if(m_atrValue<=0.0)
        {
         // Fallback: if ATR unavailable, use symbol-specific fixed stops
         if(StringFind(m_symbol,\"XAU\")>=0)
            m_stopLossPips=500;  // ~500 pips = $50 = 1% on $5000 acct
         else if(StringFind(m_symbol,\"NAS\")>=0)
            m_stopLossPips=15;   // 15 points = ~$7.50 on 0.5 lots
         else if(StringFind(m_symbol,\"US30\")>=0 || StringFind(m_symbol,\"DJ\")>=0)
            m_stopLossPips=20;   // 20 points = ~$20 on 1 lot
         else
            m_stopLossPips=50;   // generic fallback
         m_takeProfitPips=(int)(m_stopLossPips*m_rrRatio);
         return;
        }

      if(StringFind(m_symbol,\"XAU\")>=0)
        {
         // XAUUSD: SL = 0.5x ATR(H1) in pip terms
         // ATR is in price units. Convert to pips: divide by point*10 (1 pip = 10 points for XAU)
         const double pipSize=PipSize(m_symbol);
         m_stopLossPips=(int)(m_atrValue*m_atrMultiplier/pipSize);
         // Enforce minimum stop: XAUUSD needs at least 200 pips minimum
         m_stopLossPips=(int)MathMax(m_stopLossPips,200);
         // Cap maximum stop at 2000 pips (prevents runaway stops in volatile markets)
         m_stopLossPips=(int)MathMin(m_stopLossPips,2000);
        }
      else
        {
         // NAS100/US30: use fixed stops in points (indices quote in points)
         const double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
         m_stopLossPips=(int)(m_atrValue*m_atrMultiplier/point);
         m_stopLossPips=(int)MathMax(m_stopLossPips,5);
         m_stopLossPips=(int)MathMin(m_stopLossPips,500);
        }

      m_takeProfitPips=(int)(m_stopLossPips*m_rrRatio);
     }

public:
               CRiskManager()
        {
         m_symbol=\"\";
         m_riskPercent=1.0;
         m_maxDailyLoss=2.0;
         m_dailyLossCap=0.0;
         m_accountEquity=0.0;
         m_dailyPnL=0.0;
         m_sessionPnL=0.0;
         m_consecutiveLosses=0;
         m_maxConsecutiveLosses=5;
         m_lastResetDate=0;
         m_state=RISK_OK;
         m_pipValue=1.0;
         m_lastRefreshTime=0;
         m_atrMultiplier=0.5;
         m_rrRatio=3.0;
         m_atrValue=0.0;
         m_stopLossPips=0;
         m_takeProfitPips=0;
         ArrayResize(m_tradeHistory,0);
        }

   void Init(const string symbol,const double riskPercent=1.0,const double maxDailyLoss=2.0)
     {
      m_symbol=symbol;
      m_riskPercent=riskPercent;
      m_maxDailyLoss=maxDailyLoss;
      m_accountEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_pipValue=PipValuePerLot(symbol);
      m_dailyLossCap=m_accountEquity*(m_maxDailyLoss/100.0);
      ResetIfNewDay();
      ComputeATRStops();
     }

   // =====================================================================
   // DESIGN DECISION: ATR is recalculated on every Refresh() call so
   // stops adapt to current market volatility, not the volatility at init.
   // This is critical for XAUUSD which can shift from 1000 to 3000 pip ATR.
   // =====================================================================
   void Refresh()
     {
      const datetime now=TimeCurrent();
      if(now==m_lastRefreshTime)
         return;
      m_lastRefreshTime=now;
      m_accountEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      m_pipValue=PipValuePerLot(m_symbol);
      m_dailyLossCap=m_accountEquity*(m_maxDailyLoss/100.0);
      ResetIfNewDay();
      ComputeATRStops();  // recompute ATR-based stops each tick
      if(m_state==RISK_HALTED)
         return;
      if(m_dailyPnL<=-(m_dailyLossCap))
         m_state=RISK_HALTED;
      else if(m_dailyPnL<=-(m_dailyLossCap*0.5))
         m_state=RISK_WARNING;
      else
         m_state=RISK_OK;
     }

   void CheckDailyReset() { ResetIfNewDay(); }

   bool CanOpenTrade()
     {
      Refresh();
      return (m_state!=RISK_HALTED && m_consecutiveLosses<m_maxConsecutiveLosses);
     }

   // =====================================================================
   // Lot sizing: riskAmount / (stopLossPips * pipValue)
   // ATR-adaptive stops ensure lot size is correct for current volatility
   // =====================================================================
   double CalcLotSize(const double stopLossPips)
     {
      if(stopLossPips<=0.0 || m_pipValue<=0.0)
         return 0.0;
      const double riskAmount=RawRiskAmount();
      const double lots=riskAmount/(stopLossPips*m_pipValue);
      return NormalizeVolume(m_symbol,lots);
     }

   // Overload: use the precomputed ATR-adaptive stop
   double CalcLotSizeATR()
     {
      return CalcLotSize((double)GetStopLossPips());
     }

   double CalcStopLoss(const double entryPrice,const int stopLossPips,const bool isBuy)
     {
      const double pipSize=PipSize(m_symbol);
      const double distance=stopLossPips*pipSize;
      return isBuy ? entryPrice-distance : entryPrice+distance;
     }

   // Overload: use ATR-adaptive stops
   double CalcATRStopLoss(const double entryPrice,const bool isBuy)
     {
      return CalcStopLoss(entryPrice,GetStopLossPips(),isBuy);
     }

   double CalcTakeProfit(const double entryPrice,const int stopLossPips,const bool isBuy,const double rrRatio=3.0)
     {
      const double pipSize=PipSize(m_symbol);
      const double distance=stopLossPips*rrRatio*pipSize;
      return isBuy ? entryPrice+distance : entryPrice-distance;
     }

   // Overload: use ATR-adaptive TP (1:3 of ATR stop)
   double CalcARRTakeProfit(const double entryPrice,const bool isBuy)
     {
      return CalcTakeProfit(entryPrice,GetStopLossPips(),isBuy,m_rrRatio);
     }

   void RecordTrade(const double entry,const double exit,const double sl,const double tp,const double lots,const bool isWin,const bool isBuy)
     {
      STradeRecord t;
      t.entryPrice=entry;
      t.exitPrice=exit;
      t.stopLoss=sl;
      t.takeProfit=tp;
      t.lotSize=lots;
      t.isWin=isWin;
      t.isBuy=isBuy;
      t.openTime=TimeCurrent();
      t.closeTime=TimeCurrent();
      t.symbol=m_symbol;
      const double stopLossPips=MathAbs(entry-sl)/MathMax(PipSize(m_symbol),_Point);
      const double riskAmount=stopLossPips*m_pipValue*(lots>0.0 ? lots : 1.0);
      t.riskAmount=riskAmount;
      t.pnl=isWin ? riskAmount*3.0 : -riskAmount;
      const int size=ArraySize(m_tradeHistory);
      ArrayResize(m_tradeHistory,size+1);
      m_tradeHistory[size]=t;
      m_dailyPnL+=t.pnl;
      m_sessionPnL+=t.pnl;
      if(isWin) m_consecutiveLosses=0;
      else m_consecutiveLosses++;
      if(m_dailyPnL<=-(m_dailyLossCap)) m_state=RISK_HALTED;
     }

   ENUM_RISK_STATE GetState() const { return m_state; }
   double GetDailyPnL() const { return m_dailyPnL; }
   double GetEquity() const { return m_accountEquity; }
   double GetRiskPercent() const { return m_riskPercent; }
   double GetPipSize() const { return PipSize(m_symbol); }
   double GetPipValuePerLot() const { return m_pipValue; }
   void ForceDailyReset()
     {
      m_lastResetDate=0;
      ResetIfNewDay();
     }
   int GetTradeCount() const { return ArraySize(m_tradeHistory); }

   double GetTodayWinRate() const
     {
      const int total=ArraySize(m_tradeHistory);
      if(total==0) return 0.0;
      int wins=0;
      for(int i=0;i<total;i++) if(m_tradeHistory[i].isWin) wins++;
      return (double)wins/(double)total;
     }

   double GetDailyLossCap() const { return m_dailyLossCap; }
   int GetConsecutiveLosses() const { return m_consecutiveLosses; }

   // =====================================================================
   // Getters for ATR-adaptive values — used by SignalGenerator & EA
   // =====================================================================
   int GetStopLossPips() const { return m_stopLossPips; }
   int GetTakeProfitPips() const { return m_takeProfitPips; }
   double GetATRValue() const { return m_atrValue; }
   double GetRRRatio() const { return m_rrRatio; }
   void SetRRRatio(const double rr) { m_rrRatio=rr; }
   void SetATRMultiplier(const double mult) { m_atrMultiplier=mult; }
  };

#endif