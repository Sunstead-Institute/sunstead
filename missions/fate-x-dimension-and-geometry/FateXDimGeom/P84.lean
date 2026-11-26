import FateXDimGeom.Spec

namespace Problem84

theorem exists_directSum_free_free_of_projective (R M : Type) [CommRing R] [AddCommGroup M]
    [Module R M] [Module.Projective R M] : ∃ (N : Type) (_ : AddCommGroup N) (_ : Module R N),
    Module.Free R N ∧ Module.Free R (N × M) := by
  sorry

end Problem84
