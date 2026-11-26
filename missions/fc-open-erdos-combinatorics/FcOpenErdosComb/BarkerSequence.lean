/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Arxiv/2104.00502/BarkerSequence.lean#L50-L51
Upstream category: research open | AMS: 5, 11, 94
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.BarkerSequence

theorem barker_conjecture (a : List ℤ) (ha : IsBarkerSequence a) : a.length ≤ 13 := by
  sorry

end FcOpenErdosComb.BarkerSequence
