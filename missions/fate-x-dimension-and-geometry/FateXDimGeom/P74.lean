import FateXDimGeom.Spec

namespace Problem74

open IsLocalRing ModuleCat CategoryTheory

theorem IsRegularLocalRing.gorensteinAtRegularSequence {R : Type} [CommRing R]
    [IsRegularLocalRing R] {rs : List R} (reg : RingTheory.Sequence.IsRegular R rs) (y : R)
    (h : y ∉ Ideal.ofList rs) : IsGorensteinRing (R ⧸ (Ideal.ofList rs / Ideal.span {y})) := by
  sorry

end Problem74
