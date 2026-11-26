import FateXDimGeom.Spec

namespace Problem56

theorem projective_of_faithfullyFlat_base_change (R S M : Type) [CommRing R] [CommRing S]
    [Algebra R S] [Module.FaithfullyFlat R S] [AddCommGroup M] [Module R M]
    [Module.Projective S (TensorProduct R S M)] : Module.Projective R M := by
  sorry

end Problem56
