import AdditiveComb.Spec
import AdditiveComb.AP3_64

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_ap3_n64 : set_ap3_n64.length = score_ap3_n64 := by
  decide +kernel

theorem check_ap3_n64 : checkAP3Free 64 set_ap3_n64 = true := by
  decide +kernel

/-- Certifies `r_3(64) ≥ score_ap3_n64` (3-AP-free Salem–Spencer set). -/
theorem bound_ap3_n64 : ValidAP3Free 64 score_ap3_n64 :=
  validAP3Free_of_check 64 score_ap3_n64 set_ap3_n64 length_ap3_n64 check_ap3_n64

end AdditiveComb
