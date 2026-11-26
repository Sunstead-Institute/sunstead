/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/33.lean#L43-L49
Upstream category: research open | AMS: 5, 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Green33ZModBasis

open Filter
open scoped Pointwise

theorem green_33 :
    ∀ ε : ℝ, 0 < ε →
      ∃ᶠ q : ℕ+ in atTop,
        ∃ A : Finset (ZMod q),
          A + A = Finset.univ ∧
          |((A.card : ℝ) / Real.sqrt q - Real.sqrt 2)| < ε := by
  sorry

end FcOpenErdosComb.Green33ZModBasis
