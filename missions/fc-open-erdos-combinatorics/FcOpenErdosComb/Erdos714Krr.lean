/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/714.lean#L43-L47
Upstream category: research open | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.Erdos714Krr

open Filter SimpleGraph

theorem erdos_714 :
    ∀ r : ℕ, 2 ≤ r → ∃ c : ℝ, 0 < c ∧ ∀ᶠ n : ℕ in atTop,
      c * (n : ℝ) ^ ((2 : ℝ) - 1 / (r : ℝ)) ≤
        (extremalNumber n (completeBipartiteGraph (Fin r) (Fin r)) : ℝ) := by
  sorry

end FcOpenErdosComb.Erdos714Krr
