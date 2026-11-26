import CombDesigns.Spec
import CombDesigns.CA_2_15_3

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_ca_2_15_3 : checkCA2 score_ca_2_15_3 15 3 arr_ca_2_15_3 = true := by
  decide +kernel

/-- Certifies `CAN(2, 15, 3) ≤ score_ca_2_15_3`. -/
theorem bound_ca_2_15_3 : ValidCoveringArray2 15 3 score_ca_2_15_3 :=
  validCoveringArray2_of_check score_ca_2_15_3 15 3 arr_ca_2_15_3 check_ca_2_15_3

end CombDesigns
