/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/GreensOpenProblems/87.lean#L56-L58
Upstream category: research solved | AMS: 5, 20, 60
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Green87PermLimit

open Filter Asymptotics Topology

theorem green_87.variants.exists_tendsto (k : ℕ) :
    ∃ L : ℝ, Tendsto (fun n ↦ i n k) atTop (𝓝 L) := by
  sorry

end FcSolvedAlgAnal.Green87PermLimit
