/-!
Packed certificate check for `Rank444.Bound` (core Lean only, no Mathlib).

`decide +kernel` used to check all `(x, y, z)` entries one at a time, which for
⟨4,4,4⟩ meant 4096 kernel decisions over the 47 triples, run twice (contributor
build and trusted replay). `rowsOK` instead compares one packed row per `(x, y)`:
bit `z` of `rowN L x y` is entry `(x, y, z)`, so a single `Nat` equality checks a
whole row with GMP-backed `^^^`/`|||`. `entries_of_rowsOK` turns that back into the
entrywise statement used by `bound`.
-/

namespace B334

/-- entry `(x, y, z)` of `∑ₛ aₛ ⊗ bₛ ⊗ cₛ` for a list of mask triples `(aₛ, bₛ, cₛ)`, as a parity -/
def entryN : List (Nat × Nat × Nat) → Nat → Nat → Nat → Bool
  | [], _, _, _ => false
  | t :: L, x, y, z => xor (t.1.testBit x && t.2.1.testBit y && t.2.2.testBit z) (entryN L x y z)

def tgtShape (n m p x y z : Nat) : Bool :=
  decide (x % m = y / p ∧ y % p = z / n ∧ z % n = x / m)

/-- Row `(x, y)` of `∑ₛ aₛ ⊗ bₛ ⊗ cₛ`, packed: bit `z` is `entryN L x y z`. -/
def rowN : List (Nat × Nat × Nat) → Nat → Nat → Nat
  | [], _, _ => 0
  | t :: L, x, y => (if t.1.testBit x && t.2.1.testBit y then t.2.2 else 0) ^^^ rowN L x y

/-- Row `(x, y)` of the target tensor ⟨n,m,p⟩, packed over its first `k` columns. -/
def tgtRow (n m p x y : Nat) : Nat → Nat
  | 0 => 0
  | k + 1 => tgtRow n m p x y k ||| (if tgtShape n m p x y k then 2 ^ k else 0)

/-- Every packed row of `L` equals the corresponding packed row of ⟨n,m,p⟩. -/
def rowsOK (n m p : Nat) (L : List (Nat × Nat × Nat)) : Bool :=
  (List.range (n * m)).all fun x =>
    (List.range (m * p)).all fun y => rowN L x y == tgtRow n m p x y (p * n)

theorem testBit_rowN (L : List (Nat × Nat × Nat)) (x y z : Nat) :
    (rowN L x y).testBit z = entryN L x y z := by
  induction L with
  | nil => simp [rowN, entryN]
  | cons t L ih =>
    simp only [rowN, entryN, Nat.testBit_xor, ih]
    cases t.1.testBit x <;> cases t.2.1.testBit y <;> simp

theorem tgtRow_lt (n m p x y k : Nat) : tgtRow n m p x y k < 2 ^ k := by
  induction k with
  | zero => simp [tgtRow]
  | succ k ih =>
    simp only [tgtRow]
    apply Nat.or_lt_two_pow
    · exact Nat.lt_of_lt_of_le ih (Nat.pow_le_pow_right (by decide) (Nat.le_succ k))
    · split
      · exact Nat.pow_lt_pow_right (by decide) (Nat.lt_succ_self k)
      · exact Nat.two_pow_pos (k + 1)

theorem testBit_tgtRow (n m p x y k z : Nat) (hz : z < k) :
    (tgtRow n m p x y k).testBit z = tgtShape n m p x y z := by
  induction k with
  | zero => omega
  | succ k ih =>
    simp only [tgtRow, Nat.testBit_or]
    rcases Nat.lt_succ_iff_lt_or_eq.mp hz with h | h
    · rw [ih h]
      split <;> simp [Nat.ne_of_gt h]
    · subst h
      rw [Nat.testBit_lt_two_pow (tgtRow_lt n m p x y z)]
      split <;> simp_all

theorem entries_of_rowsOK (n m p : Nat) (L : List (Nat × Nat × Nat)) (h : rowsOK n m p L = true) :
    ∀ x < n * m, ∀ y < m * p, ∀ z < p * n, entryN L x y z = tgtShape n m p x y z := by
  intro x hx y hy z hz
  simp only [rowsOK, List.all_eq_true, List.mem_range, beq_iff_eq] at h
  rw [← testBit_rowN, h x hx y hy, testBit_tgtRow _ _ _ _ _ _ _ hz]

end B334
