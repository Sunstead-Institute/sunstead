import FateXIdealTheory.Spec

namespace Problem29

theorem isClosed_zpowers_iff_isOfFinOrder (K : Type)
    [Field K] [Algebra ℚ K] [Module.Finite ℚ K] (g : Field.absoluteGaloisGroup K) :
    IsClosed ((Subgroup.zpowers g) : Set (Field.absoluteGaloisGroup K)) ↔ IsOfFinOrder g := by
  sorry

end Problem29
