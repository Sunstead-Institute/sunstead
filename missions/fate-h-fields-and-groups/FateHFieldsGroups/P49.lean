import FateHFieldsGroups.Spec

theorem exists_algHom_complex_injective {F : Type} [Field F] [Algebra ℚ F]
    (h : (⊤ : IntermediateField ℚ F).FG) : ∃ f : F →ₐ[ℚ] ℂ, Function.Injective f := by
  sorry
