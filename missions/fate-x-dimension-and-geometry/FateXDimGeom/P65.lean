import FateXDimGeom.Spec

namespace Problem65

open IsLocalRing ModuleCat CategoryTheory Polynomial

theorem Polynomial.isGorensteinRing {R : Type} [CommRing R] [IsGorensteinRing R] :
    IsGorensteinRing R[X] := by
  sorry

end Problem65
