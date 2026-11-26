import FateHFieldsGroups.Spec

open Polynomial IntermediateField AdjoinRoot

theorem adjoin_add_eq_top_of_fixedField_zpowers {K L : Type} [Field K]
    [Field L] [Algebra K L] [IsGalois K L] (n a b : ℕ)
    (σ : L ≃ₐ[K] L) (hσ : orderOf σ = n) (cycle : Subgroup.zpowers σ = ⊤) (hn : n > 0)
    (hn' : n = a * b) (hab : Nat.Coprime a b) {α β : L}
    (hα : K⟮α⟯ = IntermediateField.fixedField (Subgroup.zpowers (σ ^ a)))
    (hβ : K⟮β⟯ = IntermediateField.fixedField (Subgroup.zpowers (σ ^ b))) : K⟮α + β⟯ = ⊤ := by
  sorry
