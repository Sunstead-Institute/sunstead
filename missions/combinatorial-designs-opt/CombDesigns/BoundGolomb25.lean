import CombDesigns.Spec
import CombDesigns.Golomb25

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_golomb_k25 : checkGolombRuler 25 score_golomb_k25 marks_golomb_k25 = true := by
  decide +kernel

/-- Certifies `G(25) ≤ score_golomb_k25` (a `25`-mark Golomb ruler of length `≤ score_golomb_k25`). -/
theorem bound_golomb_k25 : ValidGolombRuler 25 score_golomb_k25 :=
  validGolombRuler_of_check 25 score_golomb_k25 marks_golomb_k25 check_golomb_k25

end CombDesigns
