import FateXFieldsRingsGroups.Spec

namespace Problem14

theorem isomorphic_real_of_fractionRing_isomorphic_real_of_UFD (R : Type) [CommRing R] [IsDomain R]
    [UniqueFactorizationMonoid R] (h : Nonempty ((FractionRing R) ≃+* ℝ)) :
    Nonempty (R ≃+* ℝ) := by
  sorry

end Problem14
