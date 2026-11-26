import AdditiveComb.Spec
import AdditiveComb.Sidon100

namespace AdditiveComb

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem length_sidon_n100 : set_sidon_n100.length = score_sidon_n100 := by
  decide +kernel

theorem check_sidon_n100 : checkSidonSet 100 set_sidon_n100 = true := by
  decide +kernel

/-- Certifies a Sidon (`B_2`) set of size `score_sidon_n100` in `{0, ..., 99}`. -/
theorem bound_sidon_n100 : ValidSidonSet 100 score_sidon_n100 :=
  validSidonSet_of_check 100 score_sidon_n100 set_sidon_n100 length_sidon_n100 check_sidon_n100

end AdditiveComb
