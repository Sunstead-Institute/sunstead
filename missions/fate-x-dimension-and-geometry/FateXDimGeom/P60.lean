import FateXDimGeom.Spec

namespace Problem60

open Problem60

theorem invertible_iff_codimension_one (R : Type) [CommRing R] [IsDomain R] [IsNoetherianRing R]
    (h_ufd : ∀ (p : Ideal R), (h : p.IsMaximal) → UniqueFactorizationMonoid (Localization.AtPrime p))
    (I : Ideal R) : I.Invertible ↔ ∀ (p : associatedPrimes R I), ringKrullDim (R ⧸ p.1) = 1 := by
  sorry

end Problem60
