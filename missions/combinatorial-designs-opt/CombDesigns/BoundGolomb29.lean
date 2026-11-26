import CombDesigns.Spec
import CombDesigns.Golomb29

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_golomb_k29 : checkGolombRuler 29 score_golomb_k29 marks_golomb_k29 = true := by
  decide +kernel

/-- Certifies `G(29) ≤ score_golomb_k29` (a `29`-mark Golomb ruler of length `≤ score_golomb_k29`). -/
theorem bound_golomb_k29 : ValidGolombRuler 29 score_golomb_k29 :=
  validGolombRuler_of_check 29 score_golomb_k29 marks_golomb_k29 check_golomb_k29

end CombDesigns
