import FateXIdealTheory.Spec

namespace Problem63

theorem surjection_of_formally_unramified (R S : Type) [CommRing R] [CommRing S]
    [Algebra R S] [Algebra.FormallyUnramified R S] :
    ∃ (S' : Type) (_ : CommRing S') (_ : Algebra R S') (f : S' →ₐ[R] S), (RingHom.ker f) ^ 2 = 0 ∧ UniversalProperty.liftOfSqZeroIdeal f := by
  sorry

end Problem63
