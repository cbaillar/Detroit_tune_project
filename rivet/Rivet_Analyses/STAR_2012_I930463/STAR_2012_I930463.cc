// -*- C++ -*-
#include "Rivet/Analysis.hh"
#include "Rivet/Projections/FinalState.hh"

namespace Rivet {

  class STAR_2012_I930463: public Analysis {
    public:

      /// Constructor
      RIVET_DEFAULT_ANALYSIS_CTOR(STAR_2012_I930463);

      /// Book histograms and initialise projections before the run
      void init() {

        // Initialise and register projections
        const FinalState fs(Cuts::abseta < 1.5);
        declare(fs, "FS");

        // Book histograms
        book(_h["pT_piplus"],    1, 1, 1);
        book(_h["pT_piminus"],   1, 1, 2);
        book(_h["pT_kplus"],     1, 1, 3);
        book(_h["pT_kminus"],    1, 1, 4);
        book(_h["pT_p"],         1, 1, 5);
        book(_h["pT_pbar"],      1, 1, 6);
        book(_e["ratio_pimpip"],    7,1,1);
        book(_e["ratio_pbarp"],     7,1,2);
        book(_e["ratio_KmKp"],      7,1,3);
        book(_e["ratio_ppi"],       7,1,4);
        book(_e["ratio_pbarpibar"], 7,1,5);
        book(_e["ratio_Kpi"],       7,1,6);
        book(_h["K"],  "TMP/K+K-",   refData(7,1,6));
        book(_h["pi"], "TMP/pi+pi-", refData(7,1,6));

      }

      /// Perform the per-event analysis
      void analyze(const Event& event) {

        for (const Particle& p: apply<FinalState>(event, "FS").particles()) {

          if (p.absrap() < 0.5 && p.pT()>3*GeV) {
            const PdgId pid = p.pid();
            const double pT = p.pT() / GeV;
            switch (abs(pid)) {
              case PID::PIPLUS:
                _h["pi"]->fill(pT, 1.0/TWOPI/pT);
                _h[pid > 0? "pT_piplus" : "pT_piminus"]->fill(pT, 1.0/TWOPI/pT);
                break;
              case PID::PROTON:
                _h[pid > 0? "pT_p" : "pT_pbar"]->fill(pT, 1.0/TWOPI/pT);
                break;
              case PID::KPLUS:
                _h["K"]->fill(pT, 1.0/pT);
                _h[pid > 0? "pT_kplus" : "pT_kminus"]->fill(pT, 1.0/TWOPI/pT);
                break;
            }
          }

        } //end of loop FS particle

      } // end event ana

      /// Normalise histograms etc., after the run
      void finalize() {

        scale(_h, 1.0/sumOfWeights());

        divide(_h["pT_piminus"], _h["pT_piplus"],  _e["ratio_pimpip"]);
        divide(_h["pT_pbar"],    _h["pT_p"],       _e["ratio_pbarp"]);
        divide(_h["pT_kminus"],  _h["pT_kplus"],   _e["ratio_KmKp"]);
        divide(_h["pT_p"],       _h["pT_piplus"],  _e["ratio_ppi"]);
        divide(_h["pT_pbar"],    _h["pT_piminus"], _e["ratio_pbarpibar"]);
        divide(_h["K"],          _h["pi"],         _e["ratio_Kpi"]);

      }

    private:

      map<string,Histo1DPtr> _h;
      map<string,Estimate1DPtr> _e;
  };


  RIVET_DECLARE_PLUGIN(STAR_2012_I930463);

}
