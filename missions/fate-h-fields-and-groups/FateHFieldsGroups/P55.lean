import FateHFieldsGroups.Spec

open IntermediateField

theorem exists_pow_two_eq_algebraMap_and_adjoin_eq_top {K L : Type} [Field K] [Field L]
    [Algebra K L] [IsGalois K L] (hK : ¬ CharP K 2) : IsKleinFour (L ≃ₐ[K] L) ↔
    ∃ a b : Kˣ, ∃ x y : L, x ^ 2 = algebraMap K L a.1 ∧ y ^ 2 = algebraMap K L b.1 ∧
    K⟮x, y⟯ = ⊤ ∧ ¬IsSquare a ∧ ¬IsSquare b ∧ ¬IsSquare (a / b) := by
  sorry
