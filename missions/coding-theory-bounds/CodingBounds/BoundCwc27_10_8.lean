import CodingBounds.Spec
import CodingBounds.Cwc27_10_8

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_cwc_27_10_8 : words_cwc_27_10_8.length = score_cwc_27_10_8 := by
  decide +kernel

theorem bounds_cwc_27_10_8 : checkBounds (1 <<< 27) words_cwc_27_10_8 = true := by
  decide +kernel

theorem weights_cwc_27_10_8 : checkWeights 8 words_cwc_27_10_8 = true := by
  decide +kernel

theorem dist_cwc_27_10_8 : checkAllDist 10 words_cwc_27_10_8 = true := by
  decide +kernel

/-- Certifies `A(27, 10, 8) ≥ score_cwc_27_10_8`. -/
theorem bound_cwc_27_10_8 : ValidConstantWeightCode 27 10 8 score_cwc_27_10_8 :=
  validConstantWeightCode_of_check 27 10 8 score_cwc_27_10_8 (by decide) words_cwc_27_10_8
    length_cwc_27_10_8 bounds_cwc_27_10_8 weights_cwc_27_10_8 dist_cwc_27_10_8

end CodingBounds
