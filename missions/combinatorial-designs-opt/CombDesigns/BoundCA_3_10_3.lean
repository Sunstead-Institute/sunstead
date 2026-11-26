import CombDesigns.Spec
import CombDesigns.CA_3_10_3

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_ca_3_10_3 : checkCA3 score_ca_3_10_3 10 3 arr_ca_3_10_3 = true := by
  decide +kernel

/-- Certifies `CAN(3, 10, 3) ≤ score_ca_3_10_3`. -/
theorem bound_ca_3_10_3 : ValidCoveringArray3 10 3 score_ca_3_10_3 :=
  validCoveringArray3_of_check score_ca_3_10_3 10 3 arr_ca_3_10_3 check_ca_3_10_3

end CombDesigns
