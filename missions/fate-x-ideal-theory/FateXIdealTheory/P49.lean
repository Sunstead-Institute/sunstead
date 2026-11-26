import FateXIdealTheory.Spec

namespace Problem49

theorem principal_ideal_idempotent_iff_fg_ideal_is_direct_summand (A : Type) [CommRing A] :
    (∀ I : Ideal A, I.IsPrincipal → I ^ 2 = I) ↔
    (∀ I : Ideal A, I.FG → (∃ J : Ideal A, I ⊔ J = ⊤ ∧ I ⊓ J = ⊥ )) := by
  sorry

end Problem49
