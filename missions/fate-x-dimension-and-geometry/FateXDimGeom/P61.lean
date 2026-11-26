import FateXDimGeom.Spec

namespace Problem61

theorem formallySmooth_of_formallySmooth_quotient (R S : Type) [CommRing R] [CommRing S]
    [Algebra R S] [Module.Flat R S] (I : Ideal R) (h : I ^ 2 = 0)
    [Algebra.FormallySmooth (R ⧸ I) (S ⧸ (I.map (algebraMap R S)))] :
    Algebra.FormallySmooth R S := by
  sorry

end Problem61
