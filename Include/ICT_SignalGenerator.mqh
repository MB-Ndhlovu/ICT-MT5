/*
Project: ICT-MT5
Module: ICT_SignalGenerator
Description: Aggregates market structure, order blocks, FVGs, liquidity, kill zones, premium/discount logic, and risk checks into a final buy, sell, or no-trade decision with confidence scoring.
Author: Malibongwe Ndhlovu
Supervisor: Malibongwe Ndhlovu
Date: 2026-05-18
Dependencies: ICT_MarketStructure.mqh, ICT_OrderBlocks.mqh, ICT_FairValueGap.mqh, ICT_LiquidityPools.mqh, ICT_KillZones.mqh, ICT_PDArray.mqh, and ICT_RiskManager.mqh.
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
   bool BuyRule3() const { return (m_kz!=NULL && m_kz->IsKillZoneTrue()); }
   bool SellRule3() const { return (m_kz!=NULL && m_kz->IsKillZoneTrue()); }
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

   int RuleScore(const bool r1,const bool r2,const bool r3,const bool r4,const bool r5,const bool r6) const
     {
      const int passed=(r1?1:0)+(r2?1:0)+(r3?1:0)+(r4?1:0)+(r5?1:0)+(r6?1:0);
      return passed*10;
     }

   int BoostScore(const bool bullish,const double price) const
     {
      int score=0;
      if(m_fvg!=NULL)
         score+=(bullish ? m_fvg->GetFVGConfidence(FVG_BULL) : m_fvg->GetFVGConfidence(FVG_BEAR))/5;
      if(m_kz!=NULL)
         score+=(int)(m_kz->GetSessionProbability()*10.0);
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

   double StopBuffer() const
     {
      const double pipSize=PipSize();
      if(pipSize>0.0)
         return pipSize*2.0;
      if(m_symbol=="") return 0.0;
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
     }

   void SetRequireKillZone(const bool requireKillZone)
     {
      m_requireKillZone=requireKillZone;
     }

   SSignal CheckSignals()
     {
      SSignal sig;
      sig.direction=SIGNAL_NONE;
      sig.confidence=0;
      sig.entryPrice=0.0;
      sig.stopLoss=0.0;
      sig.takeProfit=0.0;
      sig.rrRatio=0.0;
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
      const double price=(bid+ask)*0.5;

      if(m_rm==NULL || !m_rm->CanOpenTrade())
        {
         sig.reason="Risk manager blocked trading";
         return sig;
        }
      sig.riskConfirmed=true;

      if(m_requireKillZone)
        {
         if(m_kz==NULL || !m_kz->IsKillZoneTrue())
           {
            sig.reason="Outside kill zone";
            return sig;
           }
         sig.kzConfirmed=true;
        }
      else
        {
         sig.kzConfirmed=(m_kz!=NULL && m_kz->IsKillZoneTrue());
        }

      if(m_pd==NULL || m_pd->GetDailyBias()==PD_NEUTRAL)
        {
         sig.reason="No daily bias";
         return sig;
        }

      const double pipSize=PipSize();
      if(pipSize<=0.0)
        {
         sig.reason="Unsupported pip size";
         return sig;
        }

      const bool buyR1=BuyRule1();
      const bool buyR2=BuyRule2(price);
      const bool buyR3=BuyRule3();
      const bool buyR4=BuyRule4();
      const bool buyR5=BuyRule5(price);
      const bool buyR6=BuyRule6(price);
      const bool sellR1=SellRule1();
      const bool sellR2=SellRule2(price);
      const bool sellR3=SellRule3();
      const bool sellR4=SellRule4();
      const bool sellR5=SellRule5(price);
      const bool sellR6=SellRule6(price);

      if(buyR1 && buyR2 && buyR3 && buyR4 && buyR5 && buyR6)
        {
         sig.direction=SIGNAL_BUY;
         sig.entryPrice=ask;
         sig.obConfirmed=(m_ob!=NULL && m_ob->IsPriceInBullishOBZone(price));
         sig.fvgConfirmed=(m_fvg!=NULL && m_fvg->IsPriceInBullishFVG(price));
         sig.liqConfirmed=buyR6;
         sig.bosConfirmed=buyR4;
         sig.pdBiasConfirmed=buyR1;
         const double swingLow=(m_struct!=NULL ? m_struct->GetSwingLow() : 0.0);
         const double fallbackSL=(m_fvg!=NULL ? (m_fvg->IsPriceInBullishFVG(price) ? price-StopBuffer()*2.0 : price-StopBuffer()*3.0) : price-StopBuffer()*3.0);
         sig.stopLoss=(swingLow>0.0 ? MathMin(swingLow-StopBuffer(),fallbackSL) : fallbackSL);
         const double riskPips=MathAbs(sig.entryPrice-sig.stopLoss)/pipSize;
         sig.takeProfit=m_rm->CalcTakeProfit(sig.entryPrice,(int)MathMax(1.0,riskPips),true,3.0);
         sig.rrRatio=3.0;
         sig.confidence=ClampConfidence(RuleScore(buyR1,buyR2,buyR3,buyR4,buyR5,buyR6)+BoostScore(true,price));
         sig.reason="BUY: discount + kill zone + structure + OB/FVG + liquidity";
         return sig;
        }

      if(sellR1 && sellR2 && sellR3 && sellR4 && sellR5 && sellR6)
        {
         sig.direction=SIGNAL_SELL;
         sig.entryPrice=bid;
         sig.obConfirmed=(m_ob!=NULL && m_ob->IsPriceInBearishOBZone(price));
         sig.fvgConfirmed=(m_fvg!=NULL && m_fvg->IsPriceInBearishFVG(price));
         sig.liqConfirmed=sellR6;
         sig.bosConfirmed=sellR4;
         sig.pdBiasConfirmed=sellR1;
         const double swingHigh=(m_struct!=NULL ? m_struct->GetSwingHigh() : 0.0);
         const double fallbackSL=(m_fvg!=NULL ? (m_fvg->IsPriceInBearishFVG(price) ? price+StopBuffer()*2.0 : price+StopBuffer()*3.0) : price+StopBuffer()*3.0);
         sig.stopLoss=(swingHigh>0.0 ? MathMax(swingHigh+StopBuffer(),fallbackSL) : fallbackSL);
         const double riskPips=MathAbs(sig.stopLoss-sig.entryPrice)/pipSize;
         sig.takeProfit=m_rm->CalcTakeProfit(sig.entryPrice,(int)MathMax(1.0,riskPips),false,3.0);
         sig.rrRatio=3.0;
         sig.confidence=ClampConfidence(RuleScore(sellR1,sellR2,sellR3,sellR4,sellR5,sellR6)+BoostScore(false,price));
         sig.reason="SELL: premium + kill zone + structure + OB/FVG + liquidity";
         return sig;
        }

      sig.obConfirmed=(buyR5 || sellR5);
      sig.fvgConfirmed=(buyR5 || sellR5);
      sig.liqConfirmed=(buyR6 || sellR6);
      sig.pdBiasConfirmed=(buyR1 || sellR1);
      sig.reason="Conditions not met";
      sig.confidence=ClampConfidence(MathMax(RuleScore(buyR1,buyR2,buyR3,buyR4,buyR5,buyR6),RuleScore(sellR1,sellR2,sellR3,sellR4,sellR5,sellR6))/2);
      return sig;
     }

   int GetMinConfidence() const { return m_minConfidence; }
   void SetMinConfidence(const int conf) { m_minConfidence=MathMax(0,MathMin(100,conf)); }
  };

#endif
