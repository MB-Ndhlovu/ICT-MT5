#property copyright "Malibongwe Ndhlovu"
#property link      "https://github.com/MB-Ndhlovu/ICT-MT5"
#property version   "1.01"
#property strict

#include <Trade/Trade.mqh>
#include <ICT_MarketStructure.mqh>
#include <ICT_OrderBlocks.mqh>
#include <ICT_FairValueGap.mqh>
#include <ICT_LiquidityPools.mqh>
#include <ICT_KillZones.mqh>
#include <ICT_PDArray.mqh>
#include <ICT_RiskManager.mqh>
#include <ICT_SignalGenerator.mqh>

input group "=== SYMBOL & TIMEFRAME ==="
input string         ICT_Symbol            = "XAUUSD";
input ENUM_TIMEFRAMES ICT_ExecTf           = PERIOD_M5;

input group "=== RISK MANAGEMENT ==="
input double         ICT_RiskPercent       = 1.0;
input double         ICT_MaxDailyLoss       = 2.0;
input int            ICT_MaxTrades          = 3;

input group "=== ICT MODULES ==="
input int            ICT_Lookback           = 5;
input bool           ICT_UseLondonKZ        = true;
input bool           ICT_UseNYKZ            = true;
input bool           ICT_UseHigherTFFilter   = true;

input group "=== SIGNAL FILTERING ==="
input int            ICT_MinConfidence      = 60;
input bool           ICT_UseKillZoneOnly     = true;

input group "=== BACKTESTING ==="
input double         ICT_FixedLot            = 0.0;
input bool           ICT_DebugMode          = true;

CMarketStructure g_struct;
COrderBlocks     g_ob;
CFairValueGap    g_fvg;
CLiquidityPools  g_liq;
CKillZones       g_kz;
CPDArray         g_pd;
CRiskManager     g_rm;
CSignalGenerator g_sig;
CTrade           g_trade;
int              g_tradesToday=0;
datetime         g_lastTradeDay=0;

int CurrentDayKey()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   return dt.year*10000+dt.mon*100+dt.day;
  }

void ResetDailyCountersIfNeeded()
  {
   const int day=CurrentDayKey();
   if(day!=g_lastTradeDay)
     {
      g_lastTradeDay=day;
      g_tradesToday=0;
     }
  }

int OnInit()
  {
   g_struct.Init(ICT_ExecTf,ICT_Symbol,ICT_Lookback,PERIOD_H1);
   g_ob.Init(ICT_Symbol,ICT_ExecTf,&g_struct);
   g_fvg.Init(ICT_Symbol,ICT_ExecTf);
   g_liq.Init(ICT_Symbol,ICT_ExecTf,ICT_Lookback);
   g_kz.Init();
   g_pd.Init(ICT_Symbol,PERIOD_D1);
   g_rm.Init(ICT_Symbol,ICT_RiskPercent,ICT_MaxDailyLoss);
   g_sig.Init(ICT_Symbol,&g_struct,&g_ob,&g_fvg,&g_liq,&g_kz,&g_pd,&g_rm,ICT_ExecTf);
   g_sig.SetMinConfidence(ICT_MinConfidence);
   g_lastTradeDay=CurrentDayKey();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   Print("[ICT_EA] Deinit reason=",reason);
  }

void RefreshModules()
  {
   g_struct.Refresh();
   g_ob.Refresh(20);
   g_fvg.Refresh(30);
   g_liq.Refresh();
   g_kz.Refresh();
   g_pd.Refresh();
   g_rm.Refresh();
  }

bool TradeCanProceed()
  {
   ResetDailyCountersIfNeeded();
   if(g_tradesToday>=ICT_MaxTrades)
      return false;
   return g_rm.CanOpenTrade();
  }

bool PlaceTrade(const SSignal &sig)
  {
   if(!TradeCanProceed())
      return false;
   if(PositionSelect(ICT_Symbol))
      return false;

   const double entry=(sig.direction==SIGNAL_BUY ? SymbolInfoDouble(ICT_Symbol,SYMBOL_ASK) : SymbolInfoDouble(ICT_Symbol,SYMBOL_BID));
   const double sl=sig.stopLoss;
   const double tp=sig.takeProfit;
   const double point=SymbolInfoDouble(ICT_Symbol,SYMBOL_POINT);
   const int digits=(int)SymbolInfoInteger(ICT_Symbol,SYMBOL_DIGITS);
   const double pipSize=(digits==3 || digits==5) ? point*10.0 : point;
   const double stopLossPips=MathMax(1.0,MathAbs(entry-sl)/pipSize);
   double volume=g_rm.CalcLotSize(stopLossPips);
   if(ICT_FixedLot>0.0)
      volume=ICT_FixedLot;
   if(volume<=0.0)
      return false;

   MqlTradeRequest request={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.symbol=ICT_Symbol;
   request.volume=volume;
   request.price=entry;
   request.sl=sl;
   request.tp=tp;
   request.deviation=20;
   request.type=(sig.direction==SIGNAL_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   request.type_time=ORDER_TIME_GTC;
   request.type_filling=ORDER_FILLING_FOK;

   if(!OrderSend(request,result))
     {
      Print("[ICT_EA] OrderSend failed: ",result.comment);
      return false;
     }

   if(result.retcode==TRADE_RETCODE_DONE)
     {
      g_tradesToday++;
      g_kz.MarkTradeTaken();
      if(ICT_DebugMode)
         Print("[ICT_EA] Trade opened: ",EnumToString(sig.direction)," conf=",sig.confidence," vol=",DoubleToString(volume,2)," entry=",DoubleToString(entry,_Digits)," sl=",DoubleToString(sl,_Digits)," tp=",DoubleToString(tp,_Digits));
      return true;
     }

   Print("[ICT_EA] Order rejected: ",result.retcode," / ",result.comment);
   return false;
  }

void PrintDebugStatus(const SSignal &sig)
  {
   Print("[ICT_EA] bias=",EnumToString(g_pd.GetDailyBias()),
         " kz=",g_kz.IsKillZoneTrue(),
         " state=",g_struct.StateToString(),
         " event=",g_struct.EventToString(),
         " conf=",sig.confidence,
         " dailyPnL=",DoubleToString(g_rm.GetDailyPnL(),2),
         " tradesToday=",g_tradesToday);
  }

void OnTick()
  {
   RefreshModules();
   SSignal sig=g_sig.CheckSignals();
   if(ICT_DebugMode)
      PrintDebugStatus(sig);
   if(sig.direction==SIGNAL_NONE)
      return;
   if(sig.confidence<ICT_MinConfidence)
      return;
   PlaceTrade(sig);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   const long entryType=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entryType!=DEAL_ENTRY_OUT)
      return;
   const double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   const double price=HistoryDealGetDouble(trans.deal,DEAL_PRICE);
   const double volume=HistoryDealGetDouble(trans.deal,DEAL_VOLUME);
   const long dealType=HistoryDealGetInteger(trans.deal,DEAL_TYPE);
   const bool isBuy=(dealType==DEAL_TYPE_BUY);
   g_rm.RecordTrade(price,price,price,price,volume,profit>0.0,isBuy);
   g_kz.RecordSessionResult(profit>0.0);
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const double &spread[])
  {
   return(rates_total);
  }
