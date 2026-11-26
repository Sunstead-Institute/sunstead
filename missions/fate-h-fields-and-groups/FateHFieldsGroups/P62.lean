import FateHFieldsGroups.Spec

theorem primitiveRoots_not_empty (E F : Type) [Field E] [Field F] [Algebra F E]
    (f : Polynomial F) (h_f_irr : Irreducible f) (h_splitting_field : f.IsSplittingField F E)
    (a : E) (ha : f.aeval a = 0) (n : ℕ) (hn : n ≥ 1)
    (g : Polynomial F) (h_g_irr : Irreducible g) (h_ga : g.aeval (a ^ n) = 0)
    (h_deg : f.degree = g.degree * n) (h_char : (n : F) ≠ 0) : primitiveRoots n E ≠ ∅ := by
  sorry
