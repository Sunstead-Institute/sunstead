import AdditiveComb.Spec
import AdditiveComb.CapF3_5

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_capset_f3_5 : set_capset_f3_5.length = score_capset_f3_5 := by
  decide +kernel

theorem check_capset_f3_5 : checkCapSet 5 set_capset_f3_5 = true := by
  decide +kernel

/-- Certifies a cap set of size `score_capset_f3_5` in `F_3^5`. -/
theorem bound_capset_f3_5 : ValidCapSet 5 score_capset_f3_5 :=
  validCapSet_of_check 5 score_capset_f3_5 set_capset_f3_5 length_capset_f3_5 check_capset_f3_5

end AdditiveComb
