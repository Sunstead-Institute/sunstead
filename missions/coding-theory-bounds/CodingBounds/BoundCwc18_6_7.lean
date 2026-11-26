import CodingBounds.Spec
import CodingBounds.Cwc18_6_7

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_cwc_18_6_7 : words_cwc_18_6_7.length = score_cwc_18_6_7 := by
  decide +kernel

theorem bounds_cwc_18_6_7 : checkBounds (1 <<< 18) words_cwc_18_6_7 = true := by
  decide +kernel

theorem weights_cwc_18_6_7 : checkWeights 7 words_cwc_18_6_7 = true := by
  decide +kernel

theorem dist_cwc_18_6_7 : checkAllDist 6 words_cwc_18_6_7 = true := by
  decide +kernel

/-- Certifies `A(18, 6, 7) ≥ score_cwc_18_6_7`. -/
theorem bound_cwc_18_6_7 : ValidConstantWeightCode 18 6 7 score_cwc_18_6_7 :=
  validConstantWeightCode_of_check 18 6 7 score_cwc_18_6_7 (by decide) words_cwc_18_6_7
    length_cwc_18_6_7 bounds_cwc_18_6_7 weights_cwc_18_6_7 dist_cwc_18_6_7

end CodingBounds
