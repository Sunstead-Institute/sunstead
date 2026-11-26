import AdditiveComb.Spec
import AdditiveComb.AP3_150

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_ap3_n150 : set_ap3_n150.length = score_ap3_n150 := by
  decide +kernel

theorem check_ap3_n150 : checkAP3Free 150 set_ap3_n150 = true := by
  decide +kernel

/-- Certifies `r_3(150) ≥ score_ap3_n150` (3-AP-free Salem–Spencer set). -/
theorem bound_ap3_n150 : ValidAP3Free 150 score_ap3_n150 :=
  validAP3Free_of_check 150 score_ap3_n150 set_ap3_n150 length_ap3_n150 check_ap3_n150

end AdditiveComb
