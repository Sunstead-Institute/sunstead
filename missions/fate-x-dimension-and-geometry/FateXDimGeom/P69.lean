import FateXDimGeom.Spec

namespace Problem69

open IsLocalRing Polynomial

theorem IsRegularLocalRing.regularAtPrime {R : Type} [CommRing R] [IsRegularLocalRing R]
    (P : Ideal R[X]) [P.IsPrime] [P.LiesOver (maximalIdeal R)] :
    IsRegularLocalRing (Localization.AtPrime P) := by
  sorry

end Problem69
