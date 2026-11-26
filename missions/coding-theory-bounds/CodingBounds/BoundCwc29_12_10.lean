import CodingBounds.Spec
import CodingBounds.Cwc29_12_10

namespace CodingBounds

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_cwc_29_12_10 : words_cwc_29_12_10.length = score_cwc_29_12_10 := by
  decide +kernel

theorem bounds_cwc_29_12_10 : checkBounds (1 <<< 29) words_cwc_29_12_10 = true := by
  decide +kernel

theorem weights_cwc_29_12_10 : checkWeights 10 words_cwc_29_12_10 = true := by
  decide +kernel

theorem dist_cwc_29_12_10 : checkAllDist 12 words_cwc_29_12_10 = true := by
  decide +kernel

/-- Certifies `A(29, 12, 10) ≥ score_cwc_29_12_10`. -/
theorem bound_cwc_29_12_10 : ValidConstantWeightCode 29 12 10 score_cwc_29_12_10 :=
  validConstantWeightCode_of_check 29 12 10 score_cwc_29_12_10 (by decide) words_cwc_29_12_10
    length_cwc_29_12_10 bounds_cwc_29_12_10 weights_cwc_29_12_10 dist_cwc_29_12_10

end CodingBounds
