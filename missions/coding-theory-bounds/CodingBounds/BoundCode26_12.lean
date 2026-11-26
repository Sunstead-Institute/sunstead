import CodingBounds.Spec
import CodingBounds.Code26_12

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_code_26_12 : words_code_26_12.length = score_code_26_12 := by
  decide +kernel

theorem bounds_code_26_12 : checkBounds (1 <<< 26) words_code_26_12 = true := by
  decide +kernel

theorem dist_code_26_12 : checkAllDist 12 words_code_26_12 = true := by
  decide +kernel

/-- Certifies `A(26, 12) ≥ score_code_26_12`. -/
theorem bound_code_26_12 : ValidBinaryCode 26 12 score_code_26_12 :=
  validBinaryCode_of_check 26 12 score_code_26_12 (by decide) words_code_26_12
    length_code_26_12 bounds_code_26_12 dist_code_26_12

end CodingBounds
