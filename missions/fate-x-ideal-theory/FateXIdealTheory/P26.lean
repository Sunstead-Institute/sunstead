import FateXIdealTheory.Spec

namespace Problem26

theorem card_one_or_two_of_finite_closed_subgroup_of_absoluteGaloisGroup
    (K : Type) [Field K] [Algebra ℚ K] [Module.Finite ℚ K]
    (H : Subgroup (Field.absoluteGaloisGroup K))
    (h_closed : IsClosed (H : Set (Field.absoluteGaloisGroup K)))
    (h_fin : Finite H) : Nat.card H = 1 ∨ Nat.card H = 2 := by
  sorry

end Problem26
