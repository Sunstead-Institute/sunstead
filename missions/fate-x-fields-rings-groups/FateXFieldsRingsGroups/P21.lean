import FateXFieldsRingsGroups.Spec

namespace Problem21

open Polynomial

theorem intermediateField_rank_eq_ringChar (F : Type) [Field F] (f : Polynomial F) (hf : Irreducible f)
    (K : Type) [Field K] [Algebra F K] (hK : f.IsSplittingField F K) (α : K)
    (hα : f.aeval α = 0) (hα1 : f.aeval (α + 1) = 0) :
    ∃ (E : IntermediateField F K), Module.rank E K = ringChar F := by
  sorry

end Problem21
