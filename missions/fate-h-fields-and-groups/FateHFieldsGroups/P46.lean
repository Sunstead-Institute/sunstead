import FateHFieldsGroups.Spec

open IntermediateField

theorem finrank_dvd_eight_of_add_inv_eq_algebraMap {α : ℂ} {K L : Type} [Field K] [NumberField K]
    [Algebra K ℂ] (hk : Module.finrank ℚ K = 2) {a : K} (h : α + α⁻¹ = algebraMap K ℂ a)
    [Field L] [Algebra ℚ L] [IsNormalClosure ℚ ℚ⟮a⟯ L] : Module.finrank ℚ L ∣ 8 := by
  sorry
