// -*- C++ -*-
#include "Rivet/Analysis.hh"
#include "Rivet/Projections/FinalState.hh"

namespace Rivet {

  class STAR_2006_I709170_TEST: public Analysis {
  public:
    RIVET_DEFAULT_ANALYSIS_CTOR(STAR_2006_I709170_TEST);

    void init() {
      FinalState pionfs  (Cuts::abseta < 2.5 && Cuts::pT > 0.3*GeV && Cuts::abspid == PID::PIPLUS);
      FinalState protonfs(Cuts::abseta < 2.5 && Cuts::pT > 0.4*GeV && Cuts::abspid == PID::PROTON);
      declare(pionfs,  "PionFS");
      declare(protonfs,"ProtonFS");

      // Spectra (Histo1D) — these dataset IDs exist in the STAR ref
      book(_h["pT_piplus"],      2, 1, 1);   // π+ full range
      book(_h["pT_piminus"],     7, 1, 1);   // π− full range
      book(_h["pT_proton"],     12, 1, 1);   // p
      book(_h["pT_antiproton"], 17, 1, 1);   // p̄

      // TMP pion histos: take the **x binning** from the proton/antiproton spectra.
      // This avoids any type mismatches and works even if the y-index differs across installs.
      const std::vector<double> bins_p   = refData(12, 1, 1).xEdges(); // Histo1D ref → xEdges()
      const std::vector<double> bins_pbar= refData(17, 1, 1).xEdges(); // Histo1D ref → xEdges()
      book(_h["tmp_pT_piplus"],  "TMP/pT_piplus",  bins_p);
      book(_h["tmp_pT_piminus"], "TMP/pT_piminus", bins_pbar);

      // Ratio outputs: these are BinnedEstimate<S> in the ref → use BinnedEstimatePtr<double>
      book(_e["piminus_piplus"], 23, 1, 2);
      book(_e["antipr_pr"]     , 24, 1, 2);
      book(_e["pr_piplus"]     , 25, 1, 2);
      book(_e["antipr_piminus"], 26, 1, 2);
    }

    void analyze(const Event& event) {
      const FinalState& pionfs = apply<FinalState>(event, "PionFS");
      for (const Particle& p : pionfs.particles(Cuts::absrap < 0.5)) {
        const double pT = p.pT()/GeV;
        _h[(p.pid()>0) ? "pT_piplus"     : "pT_piminus"]    ->fill(pT, 1.0/pT);
        _h[(p.pid()>0) ? "tmp_pT_piplus" : "tmp_pT_piminus"]->fill(pT, 1.0/pT);
      }

      const FinalState& protonfs = apply<FinalState>(event, "ProtonFS");
      for (const Particle& p : protonfs.particles(Cuts::absrap < 0.5)) {
        const double pT = p.pT()/GeV;
        _h[(p.pid()>0) ? "pT_proton" : "pT_antiproton"]->fill(pT, 1.0/pT);
      }
    }

    void finalize() {
      // Fill ratio BinnedEstimates directly
      divide(_h.at("pT_piminus"),    _h.at("pT_piplus"),      _e.at("piminus_piplus"));
      divide(_h.at("pT_antiproton"), _h.at("pT_proton"),      _e.at("antipr_pr"));
      divide(_h.at("pT_proton"),     _h.at("tmp_pT_piplus"),  _e.at("pr_piplus"));
      divide(_h.at("pT_antiproton"), _h.at("tmp_pT_piminus"), _e.at("antipr_piminus"));

      // Normalise spectra (ratios unaffected)
      scale(_h, 1.0 / TWOPI / sumOfWeights());
    }

  private:
    std::map<std::string, Histo1DPtr>                 _h;
    std::map<std::string, BinnedEstimatePtr<double>>  _e;
  };

  RIVET_DECLARE_PLUGIN(STAR_2006_I709170_TEST);
}