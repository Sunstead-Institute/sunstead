/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/RiemannZetaValues.lean#L72-L74
Upstream category: research open | AMS: 11, 33
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenOeisClassics.Spec

namespace FcOpenOeisClassics.IrrationalOddZeta

theorem irrational_odd (n : ℕ) (hn : 0 < n) :
    ∃ x, Irrational x ∧ riemannZeta (2 * n + 1) = x := by
  sorry

end FcOpenOeisClassics.IrrationalOddZeta
