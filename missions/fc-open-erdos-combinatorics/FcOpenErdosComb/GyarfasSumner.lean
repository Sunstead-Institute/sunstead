/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Wikipedia/GyarfasSumnerConjecture.lean#L58-L61
Upstream category: research open | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.GyarfasSumner

open SimpleGraph

theorem gyarfas_sumner_conjecture :
    ∀ {W : Type} [Fintype W] [DecidableEq W] (T : SimpleGraph W) [DecidableRel T.Adj],
      T.IsTree → ∃ f : ℕ → ℕ, IsChiBoundedBy T f := by
  sorry

end FcOpenErdosComb.GyarfasSumner
