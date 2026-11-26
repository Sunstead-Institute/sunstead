import AdditiveComb.Spec
import AdditiveComb.Sidon300

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_sidon_n300 : set_sidon_n300.length = score_sidon_n300 := by
  decide +kernel

theorem check_sidon_n300 : checkSidonSet 300 set_sidon_n300 = true := by
  decide +kernel

/-- Certifies a Sidon (`B_2`) set of size `score_sidon_n300` in `{0, ..., 299}`. -/
theorem bound_sidon_n300 : ValidSidonSet 300 score_sidon_n300 :=
  validSidonSet_of_check 300 score_sidon_n300 set_sidon_n300 length_sidon_n300 check_sidon_n300

end AdditiveComb
