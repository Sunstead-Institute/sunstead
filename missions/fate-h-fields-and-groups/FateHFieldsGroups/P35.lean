import FateHFieldsGroups.Spec

open Polynomial IntermediateField

theorem isEmpty_adjoinRoot_zMod_four {d : ℤ} (hd : Squarefree d) {a : ℚ} (ha : a ≠ 0) :
    IsEmpty ((AdjoinRoot ((a⁻¹ • X ^ 2) ^ 2 - C (d : ℚ)) ≃ₐ[ℚ]
      AdjoinRoot ((a⁻¹ • X ^ 2) ^ 2 - C (d : ℚ))) ≃* Multiplicative (ZMod 4)) := by
  sorry
