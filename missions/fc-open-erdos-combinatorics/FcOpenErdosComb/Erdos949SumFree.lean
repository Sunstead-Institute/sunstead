/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/949.lean#L40-L42
Upstream category: research open | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Erdos949SumFree

open Cardinal Filter
open scoped Pointwise Topology

theorem erdos_949 :
    ∀ S : Set ℝ, (∀ a ∈ S, ∀ b ∈ S, a + b ∉ S) → ∃ A ⊆ Sᶜ, #A = 𝔠 ∧ A + A ⊆ Sᶜ := by
  sorry

end FcOpenErdosComb.Erdos949SumFree
