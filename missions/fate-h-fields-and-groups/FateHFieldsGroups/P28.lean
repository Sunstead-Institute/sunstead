import FateHFieldsGroups.Spec

open IntermediateField

theorem exists_ratFunc_adjoin_eq_top {k : Type} [Field k] [PerfectField k] {p : ℕ} [Fact p.Prime] [CharP k p]
    {E : Type} [Field E] [Algebra (RatFunc k) E] [FiniteDimensional (RatFunc k) E] :
    ∃ α : E, (RatFunc k)⟮α⟯ = ⊤ := by
  sorry
