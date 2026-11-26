import CombDesigns.Spec
import CombDesigns.Golomb12

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_golomb_k12 : checkGolombRuler 12 score_golomb_k12 marks_golomb_k12 = true := by
  decide +kernel

/-- Certifies `G(12) ≤ score_golomb_k12` (a `12`-mark Golomb ruler of length `≤ score_golomb_k12`). -/
theorem bound_golomb_k12 : ValidGolombRuler 12 score_golomb_k12 :=
  validGolombRuler_of_check 12 score_golomb_k12 marks_golomb_k12 check_golomb_k12

end CombDesigns
