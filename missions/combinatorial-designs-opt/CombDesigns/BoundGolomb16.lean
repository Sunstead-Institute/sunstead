import CombDesigns.Spec
import CombDesigns.Golomb16

namespace CombDesigns

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem check_golomb_k16 : checkGolombRuler 16 score_golomb_k16 marks_golomb_k16 = true := by
  decide +kernel

/-- Certifies `G(16) ≤ score_golomb_k16` (a `16`-mark Golomb ruler of length `≤ score_golomb_k16`). -/
theorem bound_golomb_k16 : ValidGolombRuler 16 score_golomb_k16 :=
  validGolombRuler_of_check 16 score_golomb_k16 marks_golomb_k16 check_golomb_k16

end CombDesigns
