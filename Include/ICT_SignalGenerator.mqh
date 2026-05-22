/*
Project: ICT-MT5
Module: ICT_SignalGenerator
Description: Aggregates market structure, order blocks, FVGs, liquidity, kill zones,
              premium/discount logic, and risk checks into a final buy, sell, or no-trade
              decision with confidence scoring.
              v1.02: ATR-adaptive stops from CRiskManager
                     Gold high-conviction session filtering (NY Close weighted 1.5x)
                     Kill zone weighted probability in confidence scoring
                     XAUUSD-specific stop buffer using ATR
Author: Malibongwe Ndhlovu
Supervisor: Malibongwe Ndhlovu
Date: 2026-05-23
Dependencies: ICT_MarketStructure.mqh, ICT_OrderBlocks.mqh, ICT_FairValueGap.mqh,
              ICT_LiquidityPools.mqh, ICT_KillZones.mqh, ICT_PDArray.mqh, ICT_RiskManager.mqh.
*/
#ifndef ICT_SIGNAL_GENERATOR_MQH
#define ICT_SIGNAL_GENERATOR_MQH

#include <ICT_MarketStructure.mqh>
#include <ICT_OrderBlocks.mqh>
#include <ICT_FairValueGap.mqh>
#include <ICT_LiquidityPools.mqh>
#include <ICT_KillZones.mqh>
#include <ICT_PDArray.mqh>
#include <ICT_RiskManager.mqh>

enum ENUM_SIGNAL
  {
   SIGNAL_NONE=0,
   SIGNAL_BUY=1,
   SIGNAL_SELL=2
  };

struct SSignal
  {
   ENUM_SIGNAL direction;
   int         confidence;
   double      entryPrice;
   double      stopLoss;
   double      takeProfit;
   double      rrRatio;
   bool        obConfirmed;
   bool        fvgConfirmed;
   bool        liqConfirmed;
   bool        kzConfirmed;
   bool        bosConfirmed;
   bool        pdBiasConfirmed;
   bool        riskConfirmed;
   string      reason;
  };

class CSignalGenerator
  {
private:
   CMarketStructure *m_struct;
   COrderBlocks     *m_ob;
   CFairValueGap    *m_fvg;
   CLiquidityPools  *m_liq;
   CKillZones       *m_kz;
   CPDArray         *m_pd;
   CRiskManager     *m_rm;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_execTf;
   int               m_minConfidence;
   bool              m_requireKillZone;
   bool              m_isXAUUSD;

   double PipSize() const
     {
      if(m_rm!=NULL)
         return m_rm->GetPipSize();
      if(m_symbol=="")
         return 0.0;
      const double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      const int digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      if(StringFind(m_symbol,"XAU")>=0)
         return MathMax(point*10.0,0.1);
      if(StringFind(m_symbol,"NAS")>=0 || StringFind(m_symbol,"US30")>=0 || StringFind(m_symbol,"US 30")>=0 || StringFind(m_symbol,"DJ")>=0 || StringFind(m_symbol,"USTEC")>=0)
         return MathMax(point,1.0);
      return ((digits==3 || digits==5) ? point*10.0 : point);
     }

   bool BuyRule1() const { return (m_pd!=NULL && m_pd->GetDailyBias()==PD_BULLISH); }
   bool SellRule1() const { return (m_pd!=NULL && m_pd->GetDailyBias()==PD_BEARISH); }
   bool BuyRule2(const double price) const { return (m_pd!=NULL && m_pd->IsInDiscountZone(price)); }
   bool SellRule2(const double price) const { return (m_pd!=NULL && m_pd->IsInPremiumZone(price)); }

   // =====================================================================
   // DESIGN DECISION: Gold gets high-conviction session filter
   // NY Close (15-17 NY): xauusdWeight=1.5 — highest conviction for gold
   // This prevents trading during low-volume gold sessions (London AM)
   // =====================================================================
   bool BuyRule3() const
     {
      if(m_kz==NULL) return false;
      if(m_isXAUUSD)
         return m_kz->IsGoldHighConvictionSession(); // weight >= 1.3 for gold
      return m_kz->IsKillZoneTrue();
     }

   bool SellRule3() const
     {
      if(m_kz==NULL) return false;
      if(m_isXAUUSD)
         return m_kz->IsGoldHighConvictionSession();
      return m_kz->IsKillZoneTrue();
     }

   bool BuyRule4() const { return (m_struct!=NULL && m_struct->GetState()==STRUCTURE_BULLISH && (m_struct->GetLastEvent()==EVENT_BULLISH_BOS || m_struct->GetLastEvent()==EVENT_BULLISH_CHOCH)); }
   bool SellRule4() const { return (m_struct!=NULL && m_struct->GetState()==STRUCTURE_BEARISH && (m_struct->GetLastEvent()==EVENT_BEARISH_BOS || m_struct->GetLastEvent()==EVENT_BEARISH_CHOCH)); }

   bool BuyRule5(const double price) const
     {
      if(m_ob!=NULL && m_ob->IsPriceInBullishOBZone(price)) return true;
      if(m_fvg!=NULL && m_fvg->IsPriceInBullishFVG(price)) return true;
      return false;
     }

   bool SellRule5(const double price) const
     {
      if(m_ob!=NULL && m_ob->IsPriceInBearishOBZone(price)) return true;
      if(m_fvg!=NULL && m_fvg->IsPriceInBearishFVG(price)) return true;
      return false;
     }

   bool BuyRule6(const double price) const { return (m_liq!=NULL && m_liq->GetPoolStrength(price,true)>=5); }
   bool SellRule6(const double price) const { return (m_liq!=NULL && m_liq->GetPoolStrength(price,false)>=5); }

   int ClampConfidence(const int value) const
     {
      if(value<0) return 0;
      if(value>100) return 100;
      return value;
     }

   // =====================================================================
   // CONFIDENCE SCORING (0-100)
   // Base: 10 points per passed rule (max 60)
   // Boost: FVG, weighted kill zone probability, liquidity, OB efficiency
   //
   // Weighted kill zone probability is critical for gold:
   //   baseProb(0.52-0.60) * xauusdWeight(0.6-1.5) = 0.31-0.90
   //   Scored as 3-9 points
   // =====================================================================
   int BoostScore(const bool bullish,const double price) const
     {
      int score=0;
      if(m_fvg!=NULL)
         score+=(bullish ? m_fvg->GetFVGConfidence(FVG_BULL) : m_fvg->GetFVGConfidence(FVG_BEAR))/5;

      // Kill zone: use WEIGHTED probability for gold (accounts for session conviction)
      if(m_kz!=NULL)
        {
         const double weightedProb=m_kz->GetWeightedSessionProbability();
         score+=(int)(weightedProb*10.0); // 0-9 points based on weighted probability
        }

      if(m_liq!=NULL)
         score+=MathMin(10,m_liq->GetPoolStrength(price,bullish));

      if(m_ob!=NULL)
        {
         SOrderBlock ob;
         if(bullish && m_ob->GetNearestBullishOB(price,ob)) score+=(int)(ob.efficiency*10.0);
         if(!bullish && m_ob->GetNearestBearishOB(price,ob)) score+=(int)(ob.efficiency*10.0);
        }

      return score;
     }

   // =====================================================================
   // ATR-BASED STOP BUFFER — replaces fixed pip buffer
   // For gold: 0.5x ATR as minimum buffer (adapts to volatility)
   // For indices: use fixed buffer (indices don't need ATR adaptation)
   // =====================================================================
   double ATRStopBuffer() const
     {
      if(m_rm==NULL || m_rm->GetATRValue()<=0.0)
         return SymbolInfoDouble(m_symbol,SYMBOL_POINT)*20.0; // fallback

      if(m_isXAUUSD)
        {
         // 0.5x ATR minimum buffer for gold (matches risk manager ATR multiplier)
         const double minBuffer=m_rm->GetATRValue()*0.5;
         // Enforce minimum of 30 pips buffer
         return MathMax(minBuffer,m_rm->GetPipSize()*30.0);
        }
      return SymbolInfoDouble(m_symbol,SYMBOL_POINT)*20.0;
     }

public:
               CSignalGenerator()
     {
      m_struct=NULL;
      m_ob=NULL;
      m_fvg=NULL;
      m_liq=NULL;
      m_kz=NULL;
      m_pd=NULL;
      m_rm=NULL;
      m_symbol="";
      m_execTf=PERIOD_M5;
      m_minConfidence=60;
      m_requireKillZone=true;
      m_isXAUUSD=false;
     }

   void Init(const string symbol,CMarketStructure *structure,COrderBlocks *ob,CFairValueGap *fvg,CLiquidityPools *liq,CKillZones *kz,CPDArray *pd,CRiskManager *rm,const ENUM_TIMEFRAMES execTf=PERIOD_M5)
     {
      m_symbol=symbol;
      m_struct=structure;
      m_ob=ob;
      m_fvg=fvg;
      m_liq=liq;
      m_kz=kz;
      m_pd=pd;
      m_rm=rm;
      m_execTf=execTf;
      m_isXAUUSD=(StringFind(symbol,"XAU")>=0);
     }

   void SetRequireKillZone(const bool requireKillZone) { m_requireKillZone=requireKillZone; }
   int GetMinConfidence() const { return m_minConfidence; }
   void SetMinConfidence(const int conf) { m_minConfidence=MathMax(0,MathMin(100,conf)); }

   SSignal CheckSignals()
     {
      SSignal sig={};
      sig.direction=SIGNAL_NONE;
      sig.confidence=0;
      sig.entryPrice=0.0;
      sig.stopLoss=0.0;
      sig.takeProfit=0.0;
      sig.rrRatio=3.0;
      sig.obConfirmed=false;
      sig.fvgConfirmed=false;
      sig.liqConfirmed=false;
      sig.kzConfirmed=false;
      sig.bosConfirmed=false;
      sig.pdBiasConfirmed=false;
      sig.riskConfirmed=false;
      sig.reason="Conditions not met";

      const double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      const double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      const double mid=(bid+ask)*0.5;

      // =================================================================
      // Risk manager gate — must pass before anything else
      // =================================================================
      if(m_rm==NULL || !m_rm->CanOpenTrade())
        {
         sig.reason="Risk manager blocked trading";
         return sig;
        }
      sig.riskConfirmed=true;

      // =================================================================
      // Kill zone gate — gold uses high-conviction filter
      // NY Close (15-17 NY): xauusdWeight=1.5 → highest conviction
      // =================================================================
      if(m_requireKillZone)
        {
         if(m_kz==NULL)
           {
            sig.reason="Kill zones module unavailable";
            return sig;
           }
         if(m_isXAUUSD)
           {
            if(!m_kz->IsGoldHighConvictionSession())
              {
               sig.reason="Outside gold high-conviction session (NZ Close/London AM)";
               return sig;
              }
           }
         else
           {
            if(!m_kz->IsKillZoneTrue())
              {
               sig.reason="Outside kill zone";
               return sig;
              }
           }
         sig.kzConfirmed=true;
        }
      else
         sig.kzConfirmed=(m_kz!=NULL && m_kz->IsKillZoneTrue());

      // =================================================================
      // Daily bias gate — must have direction
      // =================================================================
      if(m_pd==NULL || m_pd->GetDailyBias()==PD_NEUTRAL)
        {
         sig.reason="No daily bias";
         return sig;
        }

      const double pipSize=PipSize();
      if(pipSize<=0.0)
        {
         sig.reason="Unsupported symbol/pip size";
         return sig;
        }

      // =================================================================
      // Rule evaluation
      // =================================================================
      const bool buyR1=BuyRule1();
      const bool buyR2=BuyRule2(mid);
      const bool buyR3=BuyRule3();
      const bool buyR4=BuyRule4();
      const bool buyR5=BuyRule5(mid);
      const bool buyR6=BuyRule6(mid);

      const bool sellR1=SellRule1();
      const bool sellR2=SellRule2(mid);
      const bool sellR3=SellRule3();
      const bool sellR4=SellRule4();
      const bool sellR5=SellRule5(mid);
      const bool sellR6=SellRule6(mid);

      // =================================================================
      // BUY SIGNAL — all 6 rules must pass
      // =================================================================
      if(buyR1 && buyR2 && buyR3 && buyR4 && buyR5 && buyR6)
        {
         sig.direction=SIGNAL_BUY;
         sig.entryPrice=ask;
         sig.obConfirmed=true;
         sig.fvgConfirmed=(m_fvg!=NULL && m_fvg->IsPriceInBullishFVG(mid));
         sig.liqConfirmed=true;
         sig.bosConfirmed=true;
         sig.pdBiasConfirmed=true;

         // =================================================================
         // ATR-ADAPTIVE STOP LOSS — key fix from stress test
         // Use CRiskManager's precomputed ATR stops instead of swing-low buffer
         // =================================================================
         sig.stopLoss=m_rm->CalcATRStopLoss(sig.entryPrice,true); // true = buy
         sig.takeProfit=m_rm->CalcARRTakeProfit(sig.entryPrice,true); // true = buy, RR=3.0

         sig.confidence=ClampConfidence(RuleScore(buyR1,buyR2,buyR3,buyR4,buyR5,buyR6)+BoostScore(true,mid));
         sig.rrRatio=m_rm->GetRRRatio();
         sig.reason="BUY: discount+kill zone+structure+OB/FVG+liq | ATR_SL:"+IntegerToString(m_rm->GetStopLossPips())+"pips | ATR_TP:"+IntegerToString(m_rm->GetTakeProfitPips())+"pips";
         return sig;
        }

      // =================================================================
      // SELL SIGNAL — all 6 rules must pass
      // =================================================================
      if(sellR1 && sellR2 && sellR3 && sellR4 && sellR5 && sellR6)
        {
         sig.direction=SIGNAL_SELL;
         sig.entryPrice=bid;
         sig.obConfirmed=true;
         sig.fvgConfirmed=(m_fvg!=NULL && m_fvg->IsPriceInBearishFVG(mid));
         sig.liqConfirmed=true;
         sig.bosConfirmed=true;
         sig.pdBiasConfirmed=true;

         sig.stopLoss=m_rm->CalcATRStopLoss(sig.entryPrice,false); // false = sell
         sig.takeProfit=m_rm->CalcARRTakeProfit(sig.entryPrice,false); // false = sell
         sig.confidence=ClampConfidence(RuleScore(sellR1,sellR2,sellR3,sellR4,sellR5,sellR6)+BoostScore(false,mid));
         sig.rrRatio=m_rm->GetRRRatio();
         sig.reason="SELL: premium+kill zone+structure+OB/FVG+liq | ATR_SL:"+IntegerToString(m_rm->GetStopLossPips())+"pips | ATR_TP:"+IntegerToString(m_rm->GetTakeProfitPips())+"pips";
         return sig;
        }

      // =================================================================
      // NO SIGNAL — partial conditions reported for debugging
      // =================================================================
      sig.obConfirmed=(buyR5 || sellR5);
      sig.fvgConfirmed=(buyR5 || sellR5);
      sig.liqConfirmed=(buyR6 || sellR6);
      sig.pdBiasConfirmed=(buyR1 || sellR1);

      const int buyScore=RuleScore(buyR1,buyR2,buyR3,buyR4,buyR5,buyR6);
      const int sellScore=RuleScore(sellR1,sellR2,sellR3,sellR4,sellR5,sellR6);
      sig.confidence=ClampConfidence(MathMax(buyScore,sellScore));
      sig.reason="Conditions not met (buy_score="+IntegerToString(buyScore)+", sell_score="+IntegerToString(sellScore)+")";
      return sig;
     }

   // Helper for EA debug output
   string GetSignalReasonSummary(const bool buyDirection) const
     {
      if(m_kz==NULL) return "KZ:N/A";
      return "KZ:"+m_kz->GetSessionName()+"|prob:"+DoubleToString(m_kz->GetWeightedSessionProbability(),2);
     }
  };

#endif