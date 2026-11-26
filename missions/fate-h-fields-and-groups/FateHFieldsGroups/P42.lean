import FateHFieldsGroups.Spec

open IntermediateField AdjoinRoot Polynomial

theorem isGalois_adjoin_iff_isSquare (K L : Type) [Field K] [Field L] (h : ¬ CharP K 2) [Algebra K L] [IsGalois K L]
    (f : (L ≃ₐ[K] L) ≃* Multiplicative (ZMod 2 × ZMod 2)) (c : Lˣ) (hc : c.1 ≠ 0)
    (hcs : ¬ IsSquare c.1) [Fact (Irreducible (X ^ 2 - C c.1))] :
    IsGalois K (AdjoinRoot (X ^ 2 - C c.1)) ↔ ∀ σ : (L ≃ₐ[K] L), IsSquare (σ c / c) := by
  sorry
