import FateHFieldsGroups.Spec

open Polynomial

theorem norm_eq_one_of_mem_rootSet (F : IntermediateField ℚ ℂ) [FiniteDimensional ℚ F] [IsGalois ℚ F]
    (h : ∀ f g : F ≃ₐ[ℚ] F, f * g = g * f) (α : F) (f : ℚ[X])
    (h_min : f = minpoly ℚ α) (ha : ‖α‖ = 1)
    (β : ℂ) (hb : β ∈ f.rootSet ℂ) : ‖β‖ = 1 := by
  sorry
