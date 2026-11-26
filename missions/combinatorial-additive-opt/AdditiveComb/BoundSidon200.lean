import AdditiveComb.Spec
import AdditiveComb.Sidon200

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_sidon_n200 : set_sidon_n200.length = score_sidon_n200 := by
  decide +kernel

theorem check_sidon_n200 : checkSidonSet 200 set_sidon_n200 = true := by
  decide +kernel

/-- Certifies a Sidon (`B_2`) set of size `score_sidon_n200` in `{0, ..., 199}`. -/
theorem bound_sidon_n200 : ValidSidonSet 200 score_sidon_n200 :=
  validSidonSet_of_check 200 score_sidon_n200 set_sidon_n200 length_sidon_n200 check_sidon_n200

end AdditiveComb
