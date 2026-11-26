import CombDesigns.Spec
import CombDesigns.Golomb20

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_golomb_k20 : checkGolombRuler 20 score_golomb_k20 marks_golomb_k20 = true := by
  decide +kernel

/-- Certifies `G(20) ≤ score_golomb_k20` (a `20`-mark Golomb ruler of length `≤ score_golomb_k20`). -/
theorem bound_golomb_k20 : ValidGolombRuler 20 score_golomb_k20 :=
  validGolombRuler_of_check 20 score_golomb_k20 marks_golomb_k20 check_golomb_k20

end CombDesigns
