import CodingBounds.Spec
import CodingBounds.Cwc20_8_7

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_cwc_20_8_7 : words_cwc_20_8_7.length = score_cwc_20_8_7 := by
  decide +kernel

theorem bounds_cwc_20_8_7 : checkBounds (1 <<< 20) words_cwc_20_8_7 = true := by
  decide +kernel

theorem weights_cwc_20_8_7 : checkWeights 7 words_cwc_20_8_7 = true := by
  decide +kernel

theorem dist_cwc_20_8_7 : checkAllDist 8 words_cwc_20_8_7 = true := by
  decide +kernel

/-- Certifies `A(20, 8, 7) ≥ score_cwc_20_8_7`. -/
theorem bound_cwc_20_8_7 : ValidConstantWeightCode 20 8 7 score_cwc_20_8_7 :=
  validConstantWeightCode_of_check 20 8 7 score_cwc_20_8_7 (by decide) words_cwc_20_8_7
    length_cwc_20_8_7 bounds_cwc_20_8_7 weights_cwc_20_8_7 dist_cwc_20_8_7

end CodingBounds
