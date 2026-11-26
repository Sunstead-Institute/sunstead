import FateXFieldsRingsGroups.Spec

namespace Problem51

theorem adicCompletion_faithfullyFlat_iff (A : Type) [CommRing A] [IsNoetherianRing A]
    (I : Ideal A) : Module.FaithfullyFlat A (AdicCompletion I A) ↔ I ≤ Ring.jacobson A := by
  sorry

end Problem51
