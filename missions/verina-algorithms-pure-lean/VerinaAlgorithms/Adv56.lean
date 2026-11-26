import VerinaAlgorithms.Spec

namespace VerinaAdv56

theorem moveZeroes_spec_satisfied (xs: List Int) (h_precond : moveZeroes_precond (xs)) :
    moveZeroes_postcond (xs) (moveZeroes (xs) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv56
