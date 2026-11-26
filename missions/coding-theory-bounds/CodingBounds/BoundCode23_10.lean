import CodingBounds.Spec
import CodingBounds.Code23_10

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_code_23_10 : words_code_23_10.length = score_code_23_10 := by
  decide +kernel

theorem bounds_code_23_10 : checkBounds (1 <<< 23) words_code_23_10 = true := by
  decide +kernel

theorem dist_code_23_10 : checkAllDist 10 words_code_23_10 = true := by
  decide +kernel

/-- Certifies `A(23, 10) ≥ score_code_23_10`. -/
theorem bound_code_23_10 : ValidBinaryCode 23 10 score_code_23_10 :=
  validBinaryCode_of_check 23 10 score_code_23_10 (by decide) words_code_23_10
    length_code_23_10 bounds_code_23_10 dist_code_23_10

end CodingBounds
