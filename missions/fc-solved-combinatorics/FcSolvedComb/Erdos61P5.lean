/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/61.lean#L87-L89
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos61P5

open Filter
open SimpleGraph
open Real

theorem erdos_61.variants.p5 :
    ∃ c > (0 : ℝ), IsErdosHajnalLowerBound (pathGraph 5) (fun n : ℕ => (n : ℝ) ^ c) := by
  sorry

end FcSolvedComb.Erdos61P5
