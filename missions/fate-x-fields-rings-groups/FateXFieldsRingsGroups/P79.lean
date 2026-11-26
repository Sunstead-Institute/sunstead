import FateXFieldsRingsGroups.Spec

namespace Problem79

open IsLocalRing ModuleCat CategoryTheory

theorem IsLocalRing.not_isCompleteIntersection.height_not_zero_and_not_one (B : Type) [CommRing B]
    [IsRegularLocalRing B] (I : Ideal B) [IsGorensteinRing (B ⧸ I)]
    (hc : ¬ IsLocalCompleteIntersectionRing (B ⧸ I)) : I.height ≠ 0 ∧ I.height ≠ 1 := by
  sorry

end Problem79
