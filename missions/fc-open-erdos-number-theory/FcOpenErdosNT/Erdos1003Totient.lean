/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1003.lean#L38-L39
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos1003Totient

open scoped Nat
open Filter

theorem erdos_1003 : Set.Infinite {n | φ n = φ (n + 1)} := by
  sorry

end FcOpenErdosNT.Erdos1003Totient
