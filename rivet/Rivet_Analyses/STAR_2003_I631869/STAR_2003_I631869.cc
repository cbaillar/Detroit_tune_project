// -*- C++ -*-
#include "Rivet/Analysis.hh"
#include "Rivet/Projections/UnstableParticles.hh"

namespace Rivet {


  /// @brief Add a short analysis description here
  class STAR_2003_I631869 : public Analysis {
  public:

    /// Constructor
    RIVET_DEFAULT_ANALYSIS_CTOR(STAR_2003_I631869);

    /// Book histograms and initialise projections before the run
    void init() {

      declare(UnstableParticles(Cuts::eta > 3.4 && Cuts::eta < 4. && Cuts::pid == 111), "np");
      book(_h, 1, 1, 1);

    }


    //   Perform the per-event analysis
    void analyze(const Event& event) {

      const Particles npParticles = apply<UnstableParticles>(event,"np").particlesByPt(Cuts::pT > 1*GeV);
      if (npParticles.empty()) vetoEvent;

      const Particle& lead = npParticles[0];

      for (const Particle& p : npParticles) {
	      pimass = p.mass()/GeV;
	      _h->fill(lead.E()/GeV, p.E()/GeV);
      }
    }


    // Normalise histograms etc., after the run
    void finalize() {

      for (auto& b : _h->bins()) {
        double piP1 = sqrt(sqr(b.xMin()) - sqr(pimass));
        double piP2 = sqrt(sqr(b.xMax()) - sqr(pimass));
        double trigpiP = piP2 - piP1;
        b.scaleW(b.xWidth()/intpow(trigpiP,3));
      }
      scale(_h, crossSection()/microbarn/sumOfWeights());
    }

    Histo1DPtr _h;
    double pimass;

  };

  RIVET_DECLARE_PLUGIN(STAR_2003_I631869);
}
