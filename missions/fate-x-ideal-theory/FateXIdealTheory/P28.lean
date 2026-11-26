import FateXIdealTheory.Spec

namespace Problem28

theorem infinite_conj_of_ne_1_absoluteGaloisGroup (K : Type)
    [Field K] [Algebra ℚ K] [Module.Finite ℚ K] (g : Field.absoluteGaloisGroup K) (h : g ≠ 1) :
    {g' : Field.absoluteGaloisGroup K | IsConj g g'}.Infinite := by
  sorry

end Problem28
