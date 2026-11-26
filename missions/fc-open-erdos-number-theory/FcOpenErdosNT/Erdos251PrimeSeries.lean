/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/251.lean#L34-L35
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos251PrimeSeries

theorem erdos_251 : Irrational (∑' n : ℕ, (Nat.nth Nat.Prime n) / (2 ^ n)) := by
  sorry

end FcOpenErdosNT.Erdos251PrimeSeries
