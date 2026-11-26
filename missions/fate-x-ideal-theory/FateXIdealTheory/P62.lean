import FateXIdealTheory.Spec

namespace Problem62

theorem adicCompletion_equiv_of_smooth (R S : Type) [CommRing R] [CommRing S]
    [Algebra R S] [Algebra.Smooth R S] (σ : S →+* R)
    (h : Function.LeftInverse σ (algebraMap R S)) (hf : Module.Free R (RingHom.ker σ).Cotangent) :
    ∃ d : ℕ, Nonempty (AdicCompletion (RingHom.ker σ) S ≃ₐ[R] MvPowerSeries (Fin d) R) := by
  sorry

end Problem62
