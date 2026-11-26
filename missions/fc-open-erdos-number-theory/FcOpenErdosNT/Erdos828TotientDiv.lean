/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/828.lean#L37-L38
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos828TotientDiv

open scoped Nat

theorem erdos_828 : ∀ a : ℤ, Set.Infinite {n : ℕ | ↑(φ n) ∣ n + a} := by
  sorry

end FcOpenErdosNT.Erdos828TotientDiv
