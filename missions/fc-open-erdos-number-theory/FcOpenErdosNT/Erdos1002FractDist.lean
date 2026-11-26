/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1002.lean#L42-L50
Upstream category: research open | AMS: 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosNT.Spec

namespace FcOpenErdosNT.Erdos1002FractDist

open Real Set Filter Finset MeasureTheory Topology

theorem erdos_1002 :
    ∃ g : ℝ → ℝ, Monotone g ∧
    Tendsto g atBot (𝓝 0) ∧
    Tendsto g atTop (𝓝 1) ∧
    letI f :=  fun (α : ℝ) (n : ℕ) ↦
      (1 / log n) * ∑ k ∈ Icc (1 : ℕ) n, (1 / 2 - Int.fract (α * k))
    ∀ c : ℝ, Tendsto (fun (n : ℕ) ↦ (volume { α | α ∈ Ioo (0 : ℝ) 1 ∧ f α n ≤ c }).toReal)
      atTop (𝓝 (g c)) := by
  sorry

end FcOpenErdosNT.Erdos1002FractDist
