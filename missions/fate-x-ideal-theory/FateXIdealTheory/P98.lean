import FateXIdealTheory.Spec

namespace Problem98

theorem exists_maximal_ideal_not_in_finite_order {K A : Type} [Field K] [NumberField K] [CommRing A]
    [IsDomain A] [Algebra K A] [Algebra.FiniteType K A] {f : A →ₐ[K] A} (hf : ∀ n > 0, f ^ n ≠ 1) :
    ∃ m : Ideal A, m.IsMaximal ∧ ∀ n > 0, m.comap (f ^ n) ≠ m := by
  sorry

end Problem98
