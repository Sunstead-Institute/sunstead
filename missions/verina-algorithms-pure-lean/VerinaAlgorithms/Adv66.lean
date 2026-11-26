import VerinaAlgorithms.Spec

namespace VerinaAdv66

theorem reverseWords_spec_satisfied (words_str: String) (h_precond : reverseWords_precond (words_str)) :
    reverseWords_postcond (words_str) (reverseWords (words_str) h_precond) h_precond := by
  -- !benchmark @start proof
  sorry

end VerinaAdv66
