import CodingBounds.Spec
import CodingBounds.Cwc21_6_5

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_cwc_21_6_5 : words_cwc_21_6_5.length = score_cwc_21_6_5 := by
  decide +kernel

theorem bounds_cwc_21_6_5 : checkBounds (1 <<< 21) words_cwc_21_6_5 = true := by
  decide +kernel

theorem weights_cwc_21_6_5 : checkWeights 5 words_cwc_21_6_5 = true := by
  decide +kernel

theorem dist_cwc_21_6_5 : checkAllDist 6 words_cwc_21_6_5 = true := by
  decide +kernel

/-- Certifies `A(21, 6, 5) ≥ score_cwc_21_6_5`. -/
theorem bound_cwc_21_6_5 : ValidConstantWeightCode 21 6 5 score_cwc_21_6_5 :=
  validConstantWeightCode_of_check 21 6 5 score_cwc_21_6_5 (by decide) words_cwc_21_6_5
    length_cwc_21_6_5 bounds_cwc_21_6_5 weights_cwc_21_6_5 dist_cwc_21_6_5

end CodingBounds
