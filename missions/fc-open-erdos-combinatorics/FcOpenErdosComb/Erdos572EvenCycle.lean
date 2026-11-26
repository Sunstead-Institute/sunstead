/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/572.lean#L46-L50
Upstream category: research open | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Erdos572EvenCycle

open Filter

theorem erdos_572 (k : ℕ) (hk : 3 ≤ k) :
    ∃ c > (0 : ℝ), ∀ᶠ (n : ℕ) in atTop,
      c * (n : ℝ) ^ (1 + 1 / (k : ℝ)) ≤
        (SimpleGraph.extremalNumber n (SimpleGraph.cycleGraph (2 * k)) : ℝ) := by
  sorry

end FcOpenErdosComb.Erdos572EvenCycle
