import CombDesigns.Spec
import CombDesigns.CA_3_20_2

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_ca_3_20_2 : checkCA3 score_ca_3_20_2 20 2 arr_ca_3_20_2 = true := by
  decide +kernel

/-- Certifies `CAN(3, 20, 2) ≤ score_ca_3_20_2`. -/
theorem bound_ca_3_20_2 : ValidCoveringArray3 20 2 score_ca_3_20_2 :=
  validCoveringArray3_of_check score_ca_3_20_2 20 2 arr_ca_3_20_2 check_ca_3_20_2

end CombDesigns
