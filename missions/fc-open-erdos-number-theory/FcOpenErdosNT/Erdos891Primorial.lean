/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/891.lean#L42-L45
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos891Primorial

open Nat Filter Finset
open scoped ArithmeticFunction.omega

theorem erdos_891 :
    ∀ k ≥ 2, ∀ᶠ n in atTop,
    ∃ m ∈ Ico n (n + ∏ i ∈ range k, i.nth Nat.Prime), k < ω m := by
  sorry

end FcOpenErdosNT.Erdos891Primorial
