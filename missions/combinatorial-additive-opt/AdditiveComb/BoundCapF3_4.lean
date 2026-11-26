import AdditiveComb.Spec
import AdditiveComb.CapF3_4

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_capset_f3_4 : set_capset_f3_4.length = score_capset_f3_4 := by
  decide +kernel

theorem check_capset_f3_4 : checkCapSet 4 set_capset_f3_4 = true := by
  decide +kernel

/-- Certifies a cap set of size `score_capset_f3_4` in `F_3^4`. -/
theorem bound_capset_f3_4 : ValidCapSet 4 score_capset_f3_4 :=
  validCapSet_of_check 4 score_capset_f3_4 set_capset_f3_4 length_capset_f3_4 check_capset_f3_4

end AdditiveComb
