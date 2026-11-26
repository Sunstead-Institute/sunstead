import FateXIdealTheory.Spec

namespace Problem32

open IsLocalRing

theorem UFD_of_adicCompletion_UFD (R : Type) [CommRing R] [IsLocalRing R] [IsNoetherianRing R]
    [IsDomain (AdicCompletion (maximalIdeal R) R)]
    [UniqueFactorizationMonoid (AdicCompletion (maximalIdeal R) R)] :
    ∃ (h : IsDomain R), UniqueFactorizationMonoid R := by
  sorry

end Problem32
