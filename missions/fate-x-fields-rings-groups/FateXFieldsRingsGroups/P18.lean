import FateXFieldsRingsGroups.Spec

namespace Problem18

theorem isEmpty_embedding_intermediateField_of_odd_degree_galois (E : Subfield ℝ) (K : Type)
    [Field K] [Algebra E K] [IsGalois E K] (n : ℕ) (h_odd : Odd n) (hn : n > 1) (h_deg_eq : Module.rank E K = n)
    (K' : IntermediateField E ℝ) (h_radical : IsRadicalTower E K') :
    IsEmpty (K →ₐ[E] K') := by
  sorry

end Problem18
