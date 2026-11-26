/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/RiemannZetaValues.lean#L91-L93
Upstream category: research solved | AMS: 11, 33
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedNT.Spec

namespace FcSolvedNT.InfiniteIrrationalAtOdd

theorem infinite_irrational_at_odd :
    { n : ℕ | ∃ x, Irrational x ∧ riemannZeta (2 * n + 1) = x }.Infinite := by
  sorry

end FcSolvedNT.InfiniteIrrationalAtOdd
