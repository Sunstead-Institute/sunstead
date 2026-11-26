import FateXDimGeom.Spec

namespace Problem68

theorem localization_jacobson_of_one_lt_ringKrullDim (R : Type) [CommRing R] [IsLocalRing R]
    [IsNoetherianRing R] (f : R) (hf : f ∈ IsLocalRing.maximalIdeal R) (ne0 : ¬ IsNilpotent f) :
    IsJacobsonRing (Localization.Away f) := by
  sorry

end Problem68
