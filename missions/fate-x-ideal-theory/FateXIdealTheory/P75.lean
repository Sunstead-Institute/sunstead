import FateXIdealTheory.Spec

namespace Problem75

open IsLocalRing ModuleCat CategoryTheory Problem75

theorem gradedAlgebra_isCohenMacaulay_iff_homogeneously_localize {A : Type} [CommRing A] [IsNoetherianRing A]
    (𝒜 : ℕ → Submodule ℤ A) [GradedAlgebra 𝒜] (h : IsField (𝒜 0)) (h1 : Algebra.adjoin (𝒜 0) (𝒜 1) = (⊤ : Subalgebra (𝒜 0) A)) : IsCohenMacaulayRing A ↔
    ∀ p : Ideal A, (_ : p.IsPrime) → p.IsHomogeneous 𝒜 →
    IsCohenMacaulayLocalRing (HomogeneousLocalization.AtPrime 𝒜 p) := by
  sorry

end Problem75
