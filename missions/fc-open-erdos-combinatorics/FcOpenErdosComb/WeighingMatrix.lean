/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/WeighingMatrix.lean#L97-L99
Upstream category: research open | AMS: 5, 15
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.WeighingMatrix

theorem weighing_matrix_conjecture (m w : ℕ) (hm : 1 ≤ m) (hw : w ≤ 4 * m) :
    ∃ W, IsWeighingMatrix (n := 4 * m) w W := by
  sorry

end FcOpenErdosComb.WeighingMatrix
