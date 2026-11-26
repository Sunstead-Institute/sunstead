/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Paper/ReedOmegaDeltaChi.lean#L55-L61
Upstream category: research open | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.ReedOmegaDeltaChi

open scoped Finset

theorem reed_omega_delta_chi_conjecture_for_finite_graphs :
  ∀ {V : Type} [Fintype V] [DecidableEq V] (G : SimpleGraph V) [DecidableRel G.Adj],
    let χ := G.chromaticNumber
    let ω := G.cliqueNum
    let Δ := G.maxDegree
    2 * χ ≤ ω + Δ + 2 := by
  sorry

end FcOpenErdosComb.ReedOmegaDeltaChi
