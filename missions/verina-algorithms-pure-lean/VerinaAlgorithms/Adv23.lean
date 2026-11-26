import VerinaAlgorithms.Spec

namespace VerinaAdv23

theorem isPowerOfTwo_spec_satisfied (n: Int) (h_precond : isPowerOfTwo_precond (n)) :
    isPowerOfTwo_postcond (n) (isPowerOfTwo (n) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv23
