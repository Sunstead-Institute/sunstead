import AdditiveComb.Spec
import AdditiveComb.Sidon150

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_sidon_n150 : set_sidon_n150.length = score_sidon_n150 := by
  decide +kernel

theorem check_sidon_n150 : checkSidonSet 150 set_sidon_n150 = true := by
  decide +kernel

/-- Certifies a Sidon (`B_2`) set of size `score_sidon_n150` in `{0, ..., 149}`. -/
theorem bound_sidon_n150 : ValidSidonSet 150 score_sidon_n150 :=
  validSidonSet_of_check 150 score_sidon_n150 set_sidon_n150 length_sidon_n150 check_sidon_n150

end AdditiveComb
