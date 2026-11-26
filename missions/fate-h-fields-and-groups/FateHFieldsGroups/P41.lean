import FateHFieldsGroups.Spec

theorem exists_finrank_eq_pow_of_dvd_finrank {F : Type} [Field F] (p : ℕ) [Fact (Nat.Prime p)]
    (h : ∀ (E : Type) [Field E] [Algebra F E] [FiniteDimensional F E],
    Module.finrank F E ≠ 1 → p ∣ Module.finrank F E)
    (E : Type) [Field E] [Algebra F E] [FiniteDimensional F E] :
    ∃ k, Module.finrank F E = p ^ k := by
  sorry
