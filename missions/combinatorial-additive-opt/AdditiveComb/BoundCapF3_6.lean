import AdditiveComb.Spec
import AdditiveComb.CapF3_6

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_capset_f3_6 : set_capset_f3_6.length = score_capset_f3_6 := by
  decide +kernel

theorem check_capset_f3_6 : checkCapSet 6 set_capset_f3_6 = true := by
  decide +kernel

/-- Certifies a cap set of size `score_capset_f3_6` in `F_3^6`. -/
theorem bound_capset_f3_6 : ValidCapSet 6 score_capset_f3_6 :=
  validCapSet_of_check 6 score_capset_f3_6 set_capset_f3_6 length_capset_f3_6 check_capset_f3_6

end AdditiveComb
