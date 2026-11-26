import FateHFieldsGroups.Spec

open IntermediateField

theorem exists_pow_p_mem_algebraMap_and_adjoin_eq_top {p : Nat} [Fact p.Prime]
    {F K : Type} [Field F] (hF : (primitiveRoots p F).Nonempty) [Field K] [Algebra F K]
    [IsGalois F K] (hK : (K ≃ₐ[F] K) ≃* Multiplicative (ZMod p × ZMod p)) :
    ∃ (α β : K), α ≠ 0 ∧ β ≠ 0 ∧ α ^ p ∈ (algebraMap F K).range ∧ β ^ p ∈ (algebraMap F K).range ∧
    IntermediateField.adjoin F {α, β} = ⊤ := by
  sorry
