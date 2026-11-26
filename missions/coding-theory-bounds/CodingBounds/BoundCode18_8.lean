import CodingBounds.Spec
import CodingBounds.Code18_8

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_code_18_8 : words_code_18_8.length = score_code_18_8 := by
  decide +kernel

theorem bounds_code_18_8 : checkBounds (1 <<< 18) words_code_18_8 = true := by
  decide +kernel

theorem dist_code_18_8 : checkAllDist 8 words_code_18_8 = true := by
  decide +kernel

/-- Certifies `A(18, 8) ≥ score_code_18_8`. -/
theorem bound_code_18_8 : ValidBinaryCode 18 8 score_code_18_8 :=
  validBinaryCode_of_check 18 8 score_code_18_8 (by decide) words_code_18_8
    length_code_18_8 bounds_code_18_8 dist_code_18_8

end CodingBounds
