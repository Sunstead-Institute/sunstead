import CodingBounds.Spec
import CodingBounds.Code21_10

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_code_21_10 : words_code_21_10.length = score_code_21_10 := by
  decide +kernel

theorem bounds_code_21_10 : checkBounds (1 <<< 21) words_code_21_10 = true := by
  decide +kernel

theorem dist_code_21_10 : checkAllDist 10 words_code_21_10 = true := by
  decide +kernel

/-- Certifies `A(21, 10) ≥ score_code_21_10`. -/
theorem bound_code_21_10 : ValidBinaryCode 21 10 score_code_21_10 :=
  validBinaryCode_of_check 21 10 score_code_21_10 (by decide) words_code_21_10
    length_code_21_10 bounds_code_21_10 dist_code_21_10

end CodingBounds
