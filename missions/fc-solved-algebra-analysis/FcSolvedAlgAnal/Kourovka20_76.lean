/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Kourovka/20_76.lean#L40-L44
Upstream category: research solved | AMS: 20
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.Kourovka20_76

theorem kourovka_20_76 :
    ¬ (∀ᵉ (p : ℕ) (hp : p.Prime) (G : Type) (_ : Group G) (hg : IsPGroup p G) (_ : Finite G) (k : ℕ)
    (h : ∀ H: Subgroup G, H.Normal ∧ IsMulCommutative H → Nat.card H ≤ p ^ k),
    (∀ H : Subgroup G, IsMulCommutative H → Nat.card H ≤ p ^ (2 * k))) := by
  sorry

end FcSolvedAlgAnal.Kourovka20_76
