/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/396.lean#L37-L38
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos396DescFac

open Nat

theorem erdos_396 : ∀ k : ℕ, ∃ n : ℕ, descFactorial n (k + 1) ∣ centralBinom n := by
  sorry

end FcOpenErdosNT.Erdos396DescFac
