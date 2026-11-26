/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/882.lean#L64-L67
Upstream category: research solved | AMS: 5, 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos882Antichain

open Finset

theorem erdos_882 :
    Filter.Tendsto (fun n : ℕ => (maxAntichainCard n : ℝ) / Real.logb 2 n)
      Filter.atTop (nhds 1) := by
  sorry

end FcSolvedComb.Erdos882Antichain
