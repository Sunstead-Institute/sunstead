import FateXDimGeom.Spec

namespace Problem81

theorem generated_by_regular_sequence_iff (R : Type) [CommRing R] [IsLocalRing R]
    [IsNoetherianRing R] (I : Ideal R) (netop : I ≠ ⊤) :
    ∃ (rs : List R), (RingTheory.Sequence.IsRegular R rs) ∧ Ideal.ofList rs = I ↔
    Module.Free (R ⧸ I) I.Cotangent ∧
    (∃ n, CategoryTheory.HasProjectiveDimensionLE (ModuleCat.of R I) n) := by
  sorry

end Problem81
