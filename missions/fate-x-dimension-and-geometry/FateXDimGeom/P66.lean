import FateXDimGeom.Spec

namespace Problem66

open RingTheory

theorem exists_eq_ofList_and_isRegular_of_perm {R : Type} [CommRing R] [IsNoetherianRing R] (I : Ideal R) (rs : List R)
    (gen : I = Ideal.ofList rs) (h₂ : Sequence.IsRegular R rs) : ∃ rs' : List R,
    I = Ideal.ofList rs' ∧ (∀ l : List R, (l.Perm rs') → Sequence.IsRegular R l) := by
  sorry

end Problem66
