import AdditiveComb.Spec
import AdditiveComb.AP3_100

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_ap3_n100 : set_ap3_n100.length = score_ap3_n100 := by
  decide +kernel

theorem check_ap3_n100 : checkAP3Free 100 set_ap3_n100 = true := by
  decide +kernel

/-- Certifies `r_3(100) ≥ score_ap3_n100` (3-AP-free Salem–Spencer set). -/
theorem bound_ap3_n100 : ValidAP3Free 100 score_ap3_n100 :=
  validAP3Free_of_check 100 score_ap3_n100 set_ap3_n100 length_ap3_n100 check_ap3_n100

end AdditiveComb
