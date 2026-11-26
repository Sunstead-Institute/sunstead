import FateXIdealTheory.Spec

namespace Problem99

theorem equiv_of_aut_equiv {A : Type} [CommRing A] [IsDomain A] [Algebra ℂ A]
    [Algebra.FiniteType ℂ A] {n : ℕ} (hn : n ≥ 1)
    (e : (A ≃ₐ[ℂ] A) ≃* (MvPolynomial (Fin n) ℂ ≃ₐ[ℂ] MvPolynomial (Fin n) ℂ)) :
    Nonempty (A ≃ₐ[ℂ] MvPolynomial (Fin n) ℂ) := by
  sorry

end Problem99
