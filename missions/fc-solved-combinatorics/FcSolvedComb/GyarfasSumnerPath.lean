/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/GyarfasSumnerConjecture.lean#L72-L74
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.GyarfasSumnerPath

open SimpleGraph

theorem gyarfas_sumner_conjecture.variants.path (n : ℕ) :
    ∃ f : ℕ → ℕ, IsChiBoundedBy (pathGraph n) f := by
  sorry

end FcSolvedComb.GyarfasSumnerPath
