import FateXDimGeom.Spec

namespace Problem58

open TensorProduct

theorem flat_of_flat_over_quotient (R S : Type) [CommRing R] [CommRing S]
    [IsLocalRing R] [IsLocalRing S] [IsNoetherianRing R] [IsNoetherianRing S] [Algebra R S]
    (h_map : Ideal.map (algebraMap R S) (IsLocalRing.maximalIdeal R) ≤ IsLocalRing.maximalIdeal S)
    (M : Type) [AddCommGroup M] [Module S M] [Module R M] [IsScalarTower R S M] [Module.Finite S M]
    (h_flat_quotient : ∀ (n : ℕ), Module.Flat (R ⧸ (IsLocalRing.maximalIdeal R) ^ n) ((R ⧸ (IsLocalRing.maximalIdeal R) ^ n) ⊗[R] M)) :
    Module.Flat R M := by
  sorry

end Problem58
