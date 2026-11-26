/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1046.lean#L93-L95
Upstream category: research solved | AMS: 30
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Erdos1046Diameter

open Polynomial Metric

theorem erdos_1046.variants.diameter : ∀ f : ℂ[X], f.Monic →
    IsConnected (closedLemniscate f) → 2 ≤ Metric.ediam (closedLemniscate f) := by
  sorry

end FcSolvedAlgAnal.Erdos1046Diameter
