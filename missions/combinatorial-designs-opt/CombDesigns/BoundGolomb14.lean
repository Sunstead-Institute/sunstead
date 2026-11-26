import CombDesigns.Spec
import CombDesigns.Golomb14

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_golomb_k14 : checkGolombRuler 14 score_golomb_k14 marks_golomb_k14 = true := by
  decide +kernel

/-- Certifies `G(14) ≤ score_golomb_k14` (a `14`-mark Golomb ruler of length `≤ score_golomb_k14`). -/
theorem bound_golomb_k14 : ValidGolombRuler 14 score_golomb_k14 :=
  validGolombRuler_of_check 14 score_golomb_k14 marks_golomb_k14 check_golomb_k14

end CombDesigns
