import CodingBounds.Spec
import CodingBounds.Cwc17_6_6

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_cwc_17_6_6 : words_cwc_17_6_6.length = score_cwc_17_6_6 := by
  decide +kernel

theorem bounds_cwc_17_6_6 : checkBounds (1 <<< 17) words_cwc_17_6_6 = true := by
  decide +kernel

theorem weights_cwc_17_6_6 : checkWeights 6 words_cwc_17_6_6 = true := by
  decide +kernel

theorem dist_cwc_17_6_6 : checkAllDist 6 words_cwc_17_6_6 = true := by
  decide +kernel

/-- Certifies `A(17, 6, 6) ≥ score_cwc_17_6_6`. -/
theorem bound_cwc_17_6_6 : ValidConstantWeightCode 17 6 6 score_cwc_17_6_6 :=
  validConstantWeightCode_of_check 17 6 6 score_cwc_17_6_6 (by decide) words_cwc_17_6_6
    length_cwc_17_6_6 bounds_cwc_17_6_6 weights_cwc_17_6_6 dist_cwc_17_6_6

end CodingBounds
