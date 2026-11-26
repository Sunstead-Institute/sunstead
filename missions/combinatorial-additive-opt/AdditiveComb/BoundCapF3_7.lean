import AdditiveComb.Spec
import AdditiveComb.CapF3_7

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_capset_f3_7 : set_capset_f3_7.length = score_capset_f3_7 := by
  decide +kernel

theorem check_capset_f3_7 : checkCapSet 7 set_capset_f3_7 = true := by
  decide +kernel

/-- Certifies a cap set of size `score_capset_f3_7` in `F_3^7`. -/
theorem bound_capset_f3_7 : ValidCapSet 7 score_capset_f3_7 :=
  validCapSet_of_check 7 score_capset_f3_7 set_capset_f3_7 length_capset_f3_7 check_capset_f3_7

end AdditiveComb
