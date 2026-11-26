import FateXIdealTheory.Spec

namespace Problem92

theorem dimension_sequences_of_one_dimensional_rings :
    (∀ (A : Type) [CommRing A] (h : ringKrullDim A = 1),
      ∃ (k : ℕ∞), (∀ (n : ℕ), ringKrullDim (MvPolynomial (Fin n) A) = a k n)) ∧
    (∀ (k : ℕ), ∃ (A : Type) (_ : CommRing A) (h : ringKrullDim A = 1),
      (∀ (n : ℕ), ringKrullDim (MvPolynomial (Fin n) A) = a k n)):= by
  sorry

end Problem92
