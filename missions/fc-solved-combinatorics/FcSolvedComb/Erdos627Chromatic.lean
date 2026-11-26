/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/627.lean#L161-L165
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos627Chromatic

open Filter SimpleGraph
open scoped Topology Asymptotics

theorem erdos_627.variants.erdos_1961 :
    ∃ c > (0 : ℝ), ∀ᶠ n : ℕ in atTop, ∃ G : SimpleGraph (Fin n),
      G.cliqueNum = 2 ∧
        c * Real.sqrt (n : ℝ) / Real.log (n : ℝ) ≤ (G.chromaticNumber.toNat : ℝ) := by
  sorry

end FcSolvedComb.Erdos627Chromatic
