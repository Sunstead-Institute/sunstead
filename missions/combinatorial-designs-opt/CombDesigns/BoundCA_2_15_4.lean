import CombDesigns.Spec
import CombDesigns.CA_2_15_4

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_ca_2_15_4 : checkCA2 score_ca_2_15_4 15 4 arr_ca_2_15_4 = true := by
  decide +kernel

/-- Certifies `CAN(2, 15, 4) ≤ score_ca_2_15_4`. -/
theorem bound_ca_2_15_4 : ValidCoveringArray2 15 4 score_ca_2_15_4 :=
  validCoveringArray2_of_check score_ca_2_15_4 15 4 arr_ca_2_15_4 check_ca_2_15_4

end CombDesigns
