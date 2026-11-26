import FateXIdealTheory.Spec

namespace Problem91

open CategoryTheory MvPolynomial

theorem pic_three_lines {k : Type} [Field k] : Nonempty <|
    CommRing.Pic (MvPolynomial (Fin 2) k ⧸ Ideal.span ({(X 0) * (X 1) * (X 0 + X 1 - 1)} :
    Set (MvPolynomial (Fin 2) k))) ≃* kˣ := by
  sorry

end Problem91
