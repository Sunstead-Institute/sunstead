import AdditiveComb.Spec
import AdditiveComb.AP3_200

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_ap3_n200 : set_ap3_n200.length = score_ap3_n200 := by
  decide +kernel

theorem check_ap3_n200 : checkAP3Free 200 set_ap3_n200 = true := by
  decide +kernel

/-- Certifies `r_3(200) ≥ score_ap3_n200` (3-AP-free Salem–Spencer set). -/
theorem bound_ap3_n200 : ValidAP3Free 200 score_ap3_n200 :=
  validAP3Free_of_check 200 score_ap3_n200 set_ap3_n200 length_ap3_n200 check_ap3_n200

end AdditiveComb
