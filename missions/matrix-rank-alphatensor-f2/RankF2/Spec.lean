import Mathlib
namespace B334

open Finset

section Tensors

variable {R : Type*} [CommSemiring R] {n₀ n₁ n₂ : ℕ}

/-- The rank-one tensor `a ⊗ b ⊗ c`: its entry `(i, j, k)` is `a i * b j * c k`. -/
def outer3 (a : Fin n₀ → R) (b : Fin n₁ → R) (c : Fin n₂ → R) : Fin n₀ → Fin n₁ → Fin n₂ → R :=
  fun i j k => a i * b j * c k

/-- `RankLE T r`: `T` is a sum of `r` rank-one tensors. -/
def RankLE (T : Fin n₀ → Fin n₁ → Fin n₂ → R) (r : ℕ) : Prop :=
  ∃ (a : Fin r → Fin n₀ → R) (b : Fin r → Fin n₁ → R) (c : Fin r → Fin n₂ → R),
    T = ∑ s, outer3 (a s) (b s) (c s)

end Tensors

/-- The matrix multiplication tensor ⟨n,m,p⟩ over F₂. Entry `(x, y, z)` is 1 iff `x = m i + j`, `y = p j + k`,
`z = n k + i` for some `i < n`, `j < m`, `k < p`. -/
def mmT (n m p : ℕ) : Fin (n * m) → Fin (m * p) → Fin (p * n) → ZMod 2 :=
  fun x y z => if x.val % m = y.val / p ∧ y.val % p = z.val / n ∧ z.val % n = x.val / m then 1 else 0
end B334
