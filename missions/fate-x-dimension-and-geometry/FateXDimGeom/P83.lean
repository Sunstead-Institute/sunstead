import FateXDimGeom.Spec

namespace Problem83

open IsLocalRing

theorem IsRegularLocalRing.flat_local_of_regular {A B : Type} [CommRing A] [CommRing B]
    [IsRegularLocalRing A] [IsNoetherianRing B] [IsLocalRing B] {f : A →+* B} (hfl : IsLocalHom f)
    (hff : f.Flat) [IsRegularLocalRing (B ⧸ (maximalIdeal A).map f)] : IsRegularLocalRing B := by
  sorry

end Problem83
