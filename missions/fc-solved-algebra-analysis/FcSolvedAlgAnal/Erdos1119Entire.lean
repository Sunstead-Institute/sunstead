/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/1119.lean#L59-L64
Upstream category: research solved | AMS: 3, 30
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Erdos1119Entire

open Cardinal Order
open scoped Cardinal

theorem erdos_1119 :
    ∀ (m : Cardinal.{0}), ℵ₀ < m → m < 𝔠 →
    ∀ F : Set (ℂ → ℂ), (∀ f ∈ F, Differentiable ℂ f) →
      (∀ z₀ : ℂ, #{y : ℂ | ∃ f ∈ F, f z₀ = y} ≤ m) →
      #F ≤ m := by
  sorry

end FcSolvedAlgAnal.Erdos1119Entire
