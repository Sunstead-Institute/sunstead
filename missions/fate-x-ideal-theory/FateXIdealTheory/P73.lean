import FateXIdealTheory.Spec

namespace Problem73

attribute [local instance] MvPolynomial.gradedAlgebra

theorem mvPolynomial_quotient_isCohenMacaulayRing_iff (k : Type) [Field k] (n : ℕ)
    (R : Type) [CommRing R] (f : (MvPolynomial (Fin n) k) →+* R) (surj : Function.Surjective f)
    (homo : (RingHom.ker f).IsHomogeneous (MvPolynomial.homogeneousSubmodule (Fin n) k))
    (le : RingHom.ker f ≤ RingHom.ker MvPolynomial.constantCoeff) :
    IsCohenMacaulayRing R ↔
    IsCohenMacaulayRing (Localization.AtPrime ((RingHom.ker MvPolynomial.constantCoeff).map f)
      (hp := Ideal.map_isPrime_of_surjective surj le (H := RingHom.ker_isPrime _))) := by
  sorry

end Problem73
