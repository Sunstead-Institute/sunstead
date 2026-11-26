/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/ErdosProblems/295.lean#L67-L70
Upstream category: research solved | AMS: 5, 11
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.Erdos295Straus

open scoped Real

theorem erdos_295.variants.erdos_straus :
    ∃ᵉ (C > 0) (O > 0), ∀ᶠ (N : ℕ) in Filter.atTop,
      (k N - (rexp 1 - 1)*N) ∈ Set.Ioc (-C) (O * N / (N : ℝ).log):= by
  sorry

end FcSolvedComb.Erdos295Straus
