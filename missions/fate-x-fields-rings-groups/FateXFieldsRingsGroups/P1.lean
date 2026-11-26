import FateXFieldsRingsGroups.Spec

namespace Problem1

theorem isPrincipalIdealRing_of_associated_or_associated {R : Type} [CommRing R] [IsDomain R]
    [UniqueFactorizationMonoid R] {p q : R} (hp : Prime p) (hq : Prime q) (hpq : ¬ Associated p q)
    (h : ∀ {x : R}, Prime x → Associated x p ∨ Associated x q) :
    IsPrincipalIdealRing R := by
  sorry

end Problem1
