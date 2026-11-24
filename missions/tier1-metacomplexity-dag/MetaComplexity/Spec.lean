/-!
FROZEN SPECIFICATION — Foundations of Meta-Complexity & Quantitative Incompressibility.

Defines injectivity, lossless compressors, and computable image/counting primitives
on finite domains (`Fin n`), sitting at the base of time-bounded Kolmogorov complexity
and the Liu-Pass OWF equivalence.
-/

namespace MetaComplexity

def Injective {α β : Type} (f : α → β) : Prop :=
  ∀ a b, f a = f b → a = b

structure LosslessCompressor (n k : Nat) where
  encode : Fin (2 ^ n) → Fin (2 ^ k)
  decode : Fin (2 ^ k) → Fin (2 ^ n)
  left_inv : ∀ x, decode (encode x) = x

/-- Count how many elements of `Fin n` satisfy a boolean predicate `P`. -/
def countFin : (n : Nat) → (Fin n → Bool) → Nat
  | 0, _ => 0
  | n + 1, P =>
      countFin n (fun i => P ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩) +
      if P ⟨n, Nat.lt_succ_self n⟩ then 1 else 0

/-- Computable helper checking whether `x` appears in `{U(0), ..., U(k-1)}`. -/
def inImageAux {m n : Nat} (U : Fin m → Fin n) (x : Fin n) : (k : Nat) → k ≤ m → Bool
  | 0, _ => false
  | k + 1, hk => (U ⟨k, hk⟩ == x) || inImageAux U x k (Nat.le_of_lt hk)

/-- Computable membership test: true iff `∃ p : Fin m, U p = x`. -/
def inImage {m n : Nat} (U : Fin m → Fin n) (x : Fin n) : Bool :=
  inImageAux U x m (Nat.le_refl m)

end MetaComplexity
