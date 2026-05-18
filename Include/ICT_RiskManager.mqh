/*
Project: ICT-MT5
Module: ICT_RiskManager
Description: Manages pip sizing, lot sizing, daily loss caps, drawdown state, and trade history so every entry respects the project's fixed risk rules.
Author: Malibongwe Ndhlovu
Supervisor: Malibongwe Ndhlovu
Date: 2026-05-18
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

   double PipSize(const string symbol) const
     {
      const double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      const int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      if(StringFind(symbol,"XAU")>=0)
         return MathMax(point*10.0,0.1);
      if(StringFind(symbol,"NAS")>=0 || StringFind(symbol,"US30")>=0 || StringFind(symbol,"US 30")>=0 || StringFind(symbol,"DJ")>=0 || StringFind(symbol,"USTEC")>=0)
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

      if(StringFind(symbol,"XAU")>=0)
         return 10.0;
      if(StringFind(symbol,"NAS")>=0 || StringFind(symbol,"US30")>=0 || StringFind(symbol,"US 30")>=0 || StringFind(symbol,"DJ")>=0 || StringFind(symbol,"USTEC")>=0)
         return 1.0;
      return 1.0;
     }

   void ResetIfNewDay()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(),dt);
      const datetime today=(datetime)StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",dt.year,dt.mon,dt.day));
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

public:
               CRiskManager()
        {
         m_symbol="";
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
     }

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

   double CalcLotSize(const double stopLossPips)
     {
      if(stopLossPips<=0.0 || m_pipValue<=0.0)
         return 0.0;
      const double riskAmount=RawRiskAmount();
      const double lots=riskAmount/(stopLossPips*m_pipValue);
      return NormalizeVolume(m_symbol,lots);
     }

   double CalcStopLoss(const double entryPrice,const int stopLossPips,const bool isBuy)
     {
      const double pipSize=PipSize(m_symbol);
      const double distance=stopLossPips*pipSize;
      return isBuy ? entryPrice-distance : entryPrice+distance;
     }

   double CalcTakeProfit(const double entryPrice,const int stopLossPips,const bool isBuy,const double rrRatio=3.0)
     {
      const double pipSize=PipSize(m_symbol);
      const double distance=stopLossPips*rrRatio*pipSize;
      return isBuy ? entryPrice+distance : entryPrice-distance;
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
  };

#endif
