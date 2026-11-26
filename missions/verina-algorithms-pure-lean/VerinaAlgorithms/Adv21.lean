import VerinaAlgorithms.Spec

namespace VerinaAdv21

theorem isPalindrome_spec_satisfied (s: String) (h_precond : isPalindrome_precond (s)) :
    isPalindrome_postcond (s) (isPalindrome (s) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv21
