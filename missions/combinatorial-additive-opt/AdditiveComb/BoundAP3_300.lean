import AdditiveComb.Spec
import AdditiveComb.AP3_300

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_ap3_n300 : set_ap3_n300.length = score_ap3_n300 := by
  decide +kernel

theorem check_ap3_n300 : checkAP3Free 300 set_ap3_n300 = true := by
  decide +kernel

/-- Certifies `r_3(300) ≥ score_ap3_n300` (3-AP-free Salem–Spencer set). -/
theorem bound_ap3_n300 : ValidAP3Free 300 score_ap3_n300 :=
  validAP3Free_of_check 300 score_ap3_n300 set_ap3_n300 length_ap3_n300 check_ap3_n300

end AdditiveComb
