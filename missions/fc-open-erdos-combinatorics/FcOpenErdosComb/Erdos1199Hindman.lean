/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1199.lean#L43-L46
Upstream category: research open | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Erdos1199Hindman

open Pointwise

theorem erdos_1199 :
    ∀ (color : ℕ → Fin 2), ∃ (A : Set ℕ),
    A.Infinite ∧ ∀ n ∈ (A+A), ∀ m ∈ (A+A), color n = color m := by
  sorry

end FcOpenErdosComb.Erdos1199Hindman
