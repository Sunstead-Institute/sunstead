import FateXDimGeom.Spec

namespace Problem40

open TensorProduct

theorem free_of_rank_iff (R : Type) [CommRing R] [IsLocalRing R] [IsReduced R]
    (h : (minimalPrimes R).Finite) (r : ℕ) (M : Type) [AddCommGroup M] [Module R M] [Module.Finite R M] :
    Module.Free R M ∧ Module.rank R M = r ↔
    (Module.rank (IsLocalRing.ResidueField R) ((IsLocalRing.ResidueField R) ⊗[R] M) = r ∧
    ∀ p ∈ minimalPrimes R,
    Module.rank (FractionRing (R ⧸ p)) ((FractionRing (R ⧸ p)) ⊗[R] M) = r) := by
  sorry

end Problem40
