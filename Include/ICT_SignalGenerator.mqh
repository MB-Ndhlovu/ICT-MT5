//+------------------------------------------------------------------+
//|  ICT Signal Generator Module                                      |
//|  File: ICT_SignalGenerator.mqh                                    |
//|  Author: Malibongwe Ndhlovu                                       |
//|  Supervisor: Ben JARVIS AI                                        |
//|  Date: 2026-05-17                                                 |
//+------------------------------------------------------------------+

#ifndef ICT_SIGNAL_GENERATOR_MQH
#define ICT_SIGNAL_GENERATOR_MQH

#include <ICT_MarketStructure.mqh>
#include <ICT_OrderBlocks.mqh>
#include <ICT_FairValueGap.mqh>
#include <ICT_LiquidityPools.mqh>
#include <ICT_KillZones.mqh>
#include <ICT_PDArray.mqh>
#include <ICT_RiskManager.mqh>

//+------------------------------------------------------------------+
//| ENUM: Signal Direction                                            |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL {
    SIGNAL_NONE,
    SIGNAL_BUY,
    SIGNAL_SELL
};

//+------------------------------------------------------------------+
//| STRUCT: Signal                                                    |
//+------------------------------------------------------------------+
struct SSignal {
    ENUM_SIGNAL  direction;      // BUY or SELL
    int         confidence;      // 0-100 composite score
    double      entryPrice;       // Suggested entry
    double      stopLoss;         // Calculated SL
    double      takeProfit;       // Calculated TP (3:1 RR)
    double      rrRatio;          // Actual RR achieved
    bool        obConfirmed;     // Order block confirmed
    bool        fvgConfirmed;    // FVG confirmed
    bool        liqConfirmed;    // Liquidity confirmed
    bool        kzConfirmed;      // Kill zone active
    bool        bosConfirmed;     // BoS confirmed
    bool        pdBiasConfirmed; // PD array bias confirmed
    string      reason;           // Human-readable reason string
};

//+------------------------------------------------------------------+
//| CLASS: CSignalGenerator                                           |
//+------------------------------------------------------------------+
class CSignalGenerator {
private:
    // Module references
    CMarketStructure *m_struct;
    COrderBlocks      *m_ob;
    CFairValueGap     *m_fvg;
    CLiquidityPools   *m_liq;
    CKillZones        *m_kz;
    CPDArray          *m_pd;
    CRiskManager      *m_rm;

    string        m_symbol;
    ENUM_TIMEFRAMES m_execTf;   // Execution timeframe (M5/M1)
    int           m_minConfidence; // Minimum confidence to signal

    // Check all 6 conditions for BUY
    bool CheckBuyConditions(double bid, SSignal &sig) {
        bool c1 = m_pd->GetDailyBias() == PD_BULLISH;           // Daily bias bullish
        bool c2 = m_pd->IsInDiscountZone(bid);                   // Price in discount
        bool c3 = m_kz->IsKillZoneActive();                      // Kill zone active
        bool c4 = m_struct->GetState() == STRUCTURE_BULLISH &&   // Structure bullish
                  m_struct->GetLastEvent() == EVENT_BULLISH_BOS;
        bool c5ob = m_ob->IsPriceInBullishOBZone(bid);           // Bullish OB nearby
        bool c5fvg = m_fvg->IsPriceInBullishFVG(bid);            // Bullish FVG nearby
        bool c6 = m_liq->GetPoolStrength(bid, true) > 5;         // Liquidity confluence

        sig.pdBiasConfirmed = c1;
        sig.kzConfirmed     = c3;
        sig.bosConfirmed    = c4;
        sig.obConfirmed     = c5ob;
        sig.fvgConfirmed    = c5fvg;
        sig.liqConfirmed    = c6;

        return c1 && c2 && c3 && c4 && c5ob && c5fvg && c6;
    }

    // Check all 6 conditions for SELL
    bool CheckSellConditions(double ask, SSignal &sig) {
        bool c1 = m_pd->GetDailyBias() == PD_BEARISH;            // Daily bias bearish
        bool c2 = m_pd->IsInPremiumZone(ask);                    // Price in premium
        bool c3 = m_kz->IsKillZoneActive();                     // Kill zone active
        bool c4 = m_struct->GetState() == STRUCTURE_BEARISH &&  // Structure bearish
                  m_struct->GetLastEvent() == EVENT_BEARISH_BOS;
        bool c5ob = m_ob->IsPriceInBearishOBZone(ask);           // Bearish OB nearby
        bool c5fvg = m_fvg->IsPriceInBearishFVG(ask);            // Bearish FVG nearby
        bool c6 = m_liq->GetPoolStrength(ask, false) > 5;       // Liquidity confluence

        sig.pdBiasConfirmed = c1;
        sig.kzConfirmed     = c3;
        sig.bosConfirmed    = c4;
        sig.obConfirmed     = c5ob;
        sig.fvgConfirmed    = c5fvg;
        sig.liqConfirmed    = c6;

        return c1 && c2 && c3 && c4 && c5ob && c5fvg && c6;
    }

    // Calculate composite confidence score
    int CalcConfidence(bool conditions[], int size, bool bullish) {
        int passed = 0;
        for(int i = 0; i < size; i++)
            if(conditions[i]) passed++;

        // Base score from conditions passed (6 conditions = 100%)
        int base = (int)((double)passed / size * 60);

        // Bonus: FVG confidence
        int fvgConf = m_fvg->GetFVGConfidence(bullish ? FVG_BULL : FVG_BEAR);
        int fvgBonus = (int)((double)fvgConf / 100.0 * 20);

        // Bonus: Kill zone probability
        double kzProb = m_kz->GetSessionProbability();
        int kzBonus = (int)(kzProb * 10);

        // Bonus: OB efficiency
        int obBonus = 0;
        SOrderBlock ob;
        if(bullish) {
            if(m_ob->GetNearestBullishOB(SymbolInfoDouble(m_symbol, SYMBOL_BID), ob))
                obBonus = (int)(ob.efficiency * 10);
        } else {
            if(m_ob->GetNearestBearishOB(SymbolInfoDouble(m_symbol, SYMBOL_ASK), ob))
                obBonus = (int)(ob.efficiency * 10);
        }

        return MathMin(base + fvgBonus + kzBonus + obBonus, 100);
    }

public:
    CSignalGenerator() {
        m_minConfidence = 60;
        m_execTf = PERIOD_M5;
    }

    // Inject module dependencies
    void Init(
        string symbol,
        CMarketStructure *structure,
        COrderBlocks *ob,
        CFairValueGap *fvg,
        CLiquidityPools *liq,
        CKillZones *kz,
        CPDArray *pd,
        CRiskManager *rm,
        ENUM_TIMEFRAMES execTf = PERIOD_M5
    ) {
        m_symbol = symbol;
        m_struct = structure;
        m_ob     = ob;
        m_fvg    = fvg;
        m_liq    = liq;
        m_kz     = kz;
        m_pd     = pd;
        m_rm     = rm;
        m_execTf = execTf;
    }

    // Main signal check — call every tick or on bar close
    SSignal CheckSignals() {
        SSignal sig;
        sig.direction = SIGNAL_NONE;
        sig.confidence = 0;
        sig.entryPrice = 0;
        sig.stopLoss = 0;
        sig.takeProfit = 0;
        sig.reason = "";

        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

        // Step 1: Risk check
        if(!m_rm->CanOpenTrade()) {
            sig.reason = "Risk manager: trading halted or max losses reached";
            return sig;
        }

        // Step 2: Kill Zone check (fast filter — discard outside KZ)
        if(!m_kz->IsKillZoneActive()) {
            sig.reason = "Outside Kill Zone — no trade";
            return sig;
        }

        // Step 3: Daily bias check
        ENUM_PD_STATE bias = m_pd->GetDailyBias();
        if(bias == PD_NEUTRAL) {
            sig.reason = "No daily bias established";
            return sig;
        }

        // Step 4: Try BUY first (price below 50%)
        if(CheckBuyConditions(bid, sig)) {
            sig.direction = SIGNAL_BUY;
            sig.entryPrice = ask;

            // Calculate SL: below recent swing low or FVG lower
            double sl = bid - (iHigh(m_symbol, m_execTf, 2) - iLow(m_symbol, m_execTf, 2)) * 0.5;
            int slPips = m_rm->CalcLotSize(sl) > 0 ? 1 : 50; // Placeholder
            sig.stopLoss = m_rm->CalcStopLoss(bid, slPips, true);
            sig.takeProfit = m_rm->CalcTakeProfit(bid, slPips, true, 3.0);
            sig.rrRatio = 3.0;

            sig.reason = "ICT BUY: Discount + BoS + Kill Zone + OB/FVG";

            // Step 5: Confidence scoring
            bool checks[6] = {sig.pdBiasConfirmed, sig.kzConfirmed, sig.bosConfirmed,
                             sig.obConfirmed, sig.fvgConfirmed, sig.liqConfirmed};
            sig.confidence = CalcConfidence(checks, 6, true);

            return sig;
        }

        // Step 5: Try SELL (price above 50%)
        if(CheckSellConditions(ask, sig)) {
            sig.direction = SIGNAL_SELL;
            sig.entryPrice = bid;

            double sl = ask + (iHigh(m_symbol, m_execTf, 2) - iLow(m_symbol, m_execTf, 2)) * 0.5;
            int slPips = m_rm->CalcLotSize(sl) > 0 ? 1 : 50;
            sig.stopLoss = m_rm->CalcStopLoss(ask, slPips, false);
            sig.takeProfit = m_rm->CalcTakeProfit(ask, slPips, false, 3.0);
            sig.rrRatio = 3.0;

            sig.reason = "ICT SELL: Premium + BoS + Kill Zone + OB/FVG";

            bool checks[6] = {sig.pdBiasConfirmed, sig.kzConfirmed, sig.bosConfirmed,
                             sig.obConfirmed, sig.fvgConfirmed, sig.liqConfirmed};
            sig.confidence = CalcConfidence(checks, 6, false);

            return sig;
        }

        sig.reason = "Conditions not met — waiting for setup";
        return sig;
    }

    // Get minimum confidence threshold
    int GetMinConfidence() {
        return m_minConfidence;
    }

    void SetMinConfidence(int conf) {
        m_minConfidence = conf;
    }
};

#endif // ICT_SIGNAL_GENERATOR_MQH
//+------------------------------------------------------------------+
//| END: ICT_SIGNAL_GENERATOR_MQH                                     |
//+------------------------------------------------------------------+