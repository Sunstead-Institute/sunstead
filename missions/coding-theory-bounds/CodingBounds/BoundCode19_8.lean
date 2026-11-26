import CodingBounds.Spec
import CodingBounds.Code19_8

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_code_19_8 : words_code_19_8.length = score_code_19_8 := by
  decide +kernel

theorem bounds_code_19_8 : checkBounds (1 <<< 19) words_code_19_8 = true := by
  decide +kernel

theorem dist_code_19_8 : checkAllDist 8 words_code_19_8 = true := by
  decide +kernel

/-- Certifies `A(19, 8) ≥ score_code_19_8`. -/
theorem bound_code_19_8 : ValidBinaryCode 19 8 score_code_19_8 :=
  validBinaryCode_of_check 19 8 score_code_19_8 (by decide) words_code_19_8
    length_code_19_8 bounds_code_19_8 dist_code_19_8

end CodingBounds
