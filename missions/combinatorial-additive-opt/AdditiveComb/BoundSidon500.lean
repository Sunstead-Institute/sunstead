import AdditiveComb.Spec
import AdditiveComb.Sidon500

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_sidon_n500 : set_sidon_n500.length = score_sidon_n500 := by
  decide +kernel

theorem check_sidon_n500 : checkSidonSet 500 set_sidon_n500 = true := by
  decide +kernel

/-- Certifies a Sidon (`B_2`) set of size `score_sidon_n500` in `{0, ..., 499}`. -/
theorem bound_sidon_n500 : ValidSidonSet 500 score_sidon_n500 :=
  validSidonSet_of_check 500 score_sidon_n500 set_sidon_n500 length_sidon_n500 check_sidon_n500

end AdditiveComb
