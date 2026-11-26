import FateXDimGeom.Spec

namespace Problem45

theorem free_of_free_resolution {k : Type} [Field k] {r : ℕ}
    (C : ChainComplex (ModuleCat.{0} (MvPolynomial (Fin r) k)) ℕ)
    (hC : ∀ (n : ℕ), n > (r + 1) → CategoryTheory.Limits.IsZero (C.X n))
    (𝓜 : ∀ (n : ℕ), (ℕ → Submodule (MvPolynomial (Fin r) k) (C.X n)))
    [hM : ∀ (n : ℕ), DirectSum.Decomposition (𝓜 n)]
    [hM' : ∀ (n : ℕ), SetLike.GradedSMul (MvPolynomial.homogeneousSubmodule (Fin r) k) (𝓜 n)]
    (h_exact : C.Acyclic)
    (h_gr : ∀ (i j : ℕ), IsGradedHom (𝓜 i) (𝓜 j) (C.d i j).hom)
    (h_free : ∀ (n : ℕ), 1 ≤ n ∧ n ≤ r → Module.Free (MvPolynomial (Fin r) k) (C.X n)) :
    Module.Free (MvPolynomial (Fin r) k) (C.X (r + 1)) := by
  sorry

end Problem45
