/-!
# Extended Matrix Multiplication Tensor Rank over `F_2` (`⟨n, m, p⟩`, 26 Open Shapes)

Pure Lean 4.36.0 (zero Mathlib) specification of bilinear matrix multiplication tensor
rank over `F_2` (`Bool` with `xor` as addition and `&&` as multiplication), anchored to
the open benchmark catalog in `dronperminov/FastMatrixMultiplication@f70078cd9d` (MIT):

```markdown
# Rank comparison

The table below summarizes the current state of researched matrix multiplication schemes. It highlights where ternary
schemes (`ZT`) match or approximate the known minimal ranks from other fields.

|   Format   | `ZT` rank | `Z` rank | `Q` rank |        ω        |
|:----------:|:---------:|:--------:|:--------:|:---------------:|
|  `3x3x5`   |    36     |    36    |    36    |   2.824142367   |
|  `4x5x5`   |    76     |    76    |    76    |   2.821220388   |
|  `5x5x5`   |    93     |    93    |    93    |   2.816262409   |
|  `6x6x6`   |    153    |   153    |   153    |   2.807540860   |
```

This module defines:
1. `mmT n m p` — the `⟨n, m, p⟩` matrix multiplication tensor over `F_2`.
2. `RankLE n m p r` — existence of an `r`-term rank-1 outer-product decomposition of `mmT n m p`.
3. `matMulF2` and `bilinear_of_rankLE` — formal proof that `RankLE n m p r` yields an
   exact `r`-product bilinear algorithm computing `A * B` for all `A : Fin n → Fin m → Bool`
   and `B : Fin m → Fin p → Bool`.
4. `checkBrentF2` and `rankLE_of_checkBrentF2` — bit-packed Brent-equation kernel checker
   verifying all `(n*m)*(m*p)*(p*n)` equations simultaneously across `z` using `Nat.xor`
   bitmasks inside `decide +kernel`.
-/

namespace RankF2Ext

/-! ## Finite `F_2` (`Bool`) XOR-Sums -/

/-- Left-folded XOR-sum `⨁_{k < m} f k`. -/
def xorSumAux (f : Nat → Bool) : Nat → Bool
  | 0 => false
  | k + 1 => xor (xorSumAux f k) (f k)

/-- Finite XOR-sum `⨁_{s : Fin r} f s` over `F_2`. -/
def xorSum (r : Nat) (f : Fin r → Bool) : Bool :=
  xorSumAux (fun s => if h : s < r then f ⟨s, h⟩ else false) r

private theorem xor_assoc_b (a b c : Bool) : xor (xor a b) c = xor a (xor b c) := by
  cases a <;> cases b <;> cases c <;> rfl

private theorem xor_four_b (a b c d : Bool) :
    xor (xor a b) (xor c d) = xor (xor a c) (xor b d) := by
  cases a <;> cases b <;> cases c <;> cases d <;> rfl

private theorem and_xor_left_b (a b c : Bool) : (xor a b && c) = xor (a && c) (b && c) := by
  cases a <;> cases b <;> cases c <;> rfl

private theorem and_xor_right_b (a b c : Bool) : (a && xor b c) = xor (a && b) (a && c) := by
  cases a <;> cases b <;> cases c <;> rfl

private theorem xorSumAux_congr (f g : Nat → Bool) :
    ∀ k, (∀ i, i < k → f i = g i) → xorSumAux f k = xorSumAux g k
  | 0, _ => rfl
  | k + 1, h => by
    simp only [xorSumAux]
    rw [xorSumAux_congr f g k (fun i hi => h i (by omega)), h k (by omega)]

private theorem xorSumAux_false : ∀ k, xorSumAux (fun _ => false) k = false
  | 0 => rfl
  | k + 1 => by simp [xorSumAux, xorSumAux_false k]

private theorem xorSumAux_xor (f g : Nat → Bool) :
    ∀ k, xorSumAux (fun i => xor (f i) (g i)) k = xor (xorSumAux f k) (xorSumAux g k)
  | 0 => rfl
  | k + 1 => by
    simp only [xorSumAux, xorSumAux_xor f g k]
    exact xor_four_b _ _ _ _

private theorem xorSumAux_and_left (f : Nat → Bool) (c : Bool) :
    ∀ k, (xorSumAux f k && c) = xorSumAux (fun i => f i && c) k
  | 0 => by simp [xorSumAux]
  | k + 1 => by
    simp only [xorSumAux, and_xor_left_b, xorSumAux_and_left f c k]

private theorem xorSumAux_and_right (c : Bool) (f : Nat → Bool) :
    ∀ k, (c && xorSumAux f k) = xorSumAux (fun i => c && f i) k
  | 0 => by simp [xorSumAux]
  | k + 1 => by
    simp only [xorSumAux, and_xor_right_b, xorSumAux_and_right c f k]

private theorem xorSumAux_swap (f : Nat → Nat → Bool) (m : Nat) :
    ∀ n, xorSumAux (fun i => xorSumAux (fun j => f i j) m) n =
      xorSumAux (fun j => xorSumAux (fun i => f i j) n) m
  | 0 => by simp [xorSumAux, xorSumAux_false]
  | n + 1 => by
    simp only [xorSumAux, xorSumAux_swap f m n, ← xorSumAux_xor]

private theorem xorSumAux_single (j : Nat) (v : Bool) :
    ∀ n, xorSumAux (fun i => if i = j then v else false) n = if j < n then v else false
  | 0 => by simp [xorSumAux]
  | n + 1 => by
    simp only [xorSumAux, xorSumAux_single j v n]
    by_cases hlt : j < n
    · have hne : n ≠ j := by omega
      have hlt1 : j < n + 1 := by omega
      simp [hlt, hlt1, hne]
    · by_cases heq : n = j
      · subst heq
        simp
      · have hgt : ¬ (j < n + 1) := by omega
        simp [hlt, hgt, heq]

private theorem xorSumAux_add (f : Nat → Bool) (a : Nat) :
    ∀ b, xorSumAux f (a + b) = xor (xorSumAux f a) (xorSumAux (fun j => f (a + j)) b)
  | 0 => by simp [xorSumAux]
  | b + 1 => by
    rw [← Nat.add_assoc, xorSumAux, xorSumAux_add f a b, xorSumAux, xor_assoc_b]

private theorem xorSumAux_mul (f : Nat → Bool) (b : Nat) :
    ∀ a, xorSumAux f (a * b) = xorSumAux (fun i => xorSumAux (fun j => f (b * i + j)) b) a
  | 0 => by simp [xorSumAux]
  | a + 1 => by
    rw [Nat.succ_mul, xorSumAux_add, xorSumAux_mul f b a, xorSumAux]
    congr 1
    apply xorSumAux_congr
    intro j _
    rw [Nat.mul_comm]

/-! ## Matrix Multiplication Tensor `mmT` and Bilinear Rank `RankLE` -/

/-- The `⟨n, m, p⟩` matrix multiplication tensor over `F_2`.
Entry `(x, y, z)` is `true` iff `x = m*i + j`, `y = p*j + k`, `z = n*k + i`
for some `i < n`, `j < m`, `k < p`. -/
def mmT (n m p : Nat) (x : Fin (n * m)) (y : Fin (m * p)) (z : Fin (p * n)) : Bool :=
  decide (x.val % m = y.val / p ∧ y.val % p = z.val / n ∧ z.val % n = x.val / m)

/-- `RankLE n m p r`: the matrix multiplication tensor `⟨n, m, p⟩` over `F_2`
admits a bilinear rank-`r` outer-product decomposition. -/
def RankLE (n m p r : Nat) : Prop :=
  ∃ (a : Fin r → Fin (n * m) → Bool)
    (b : Fin r → Fin (m * p) → Bool)
    (c : Fin r → Fin (p * n) → Bool),
    ∀ (x : Fin (n * m)) (y : Fin (m * p)) (z : Fin (p * n)),
      xorSum r (fun s => a s x && b s y && c s z) = mmT n m p x y z

/-- Standard matrix multiplication `(A * B)[i, k] = ⨁_{j < m} A[i, j] ∧ B[j, k]` over `F_2`. -/
def matMulF2 (n m p : Nat) (A : Fin n → Fin m → Bool) (B : Fin m → Fin p → Bool)
    (i : Fin n) (k : Fin p) : Bool :=
  xorSum m (fun j => A i j && B j k)

private theorem idx_mul_add_lt {a b i j : Nat} (hi : i < a) (hj : j < b) :
    b * i + j < a * b :=
  calc b * i + j < b * i + b := Nat.add_lt_add_left hj (b * i)
    _ = b * (i + 1) := (Nat.mul_succ b i).symm
    _ ≤ b * a := Nat.mul_le_mul_left b hi
    _ = a * b := Nat.mul_comm b a

/-- Linear functional evaluating a mask `u : Fin (n * m) → Bool` against matrix `A`. -/
def evalLinA (n m : Nat) (u : Fin (n * m) → Bool) (A : Fin n → Fin m → Bool) : Bool :=
  xorSum n (fun i => xorSum m (fun j => u ⟨m * i.val + j.val, idx_mul_add_lt i.isLt j.isLt⟩ && A i j))

/-- Linear functional evaluating a mask `v : Fin (m * p) → Bool` against matrix `B`. -/
def evalLinB (m p : Nat) (v : Fin (m * p) → Bool) (B : Fin m → Fin p → Bool) : Bool :=
  xorSum m (fun j => xorSum p (fun k => v ⟨p * j.val + k.val, idx_mul_add_lt j.isLt k.isLt⟩ && B j k))

private theorem evalLinA_eq_flat (n m : Nat) (hm : 0 < m)
    (u : Fin (n * m) → Bool) (A : Fin n → Fin m → Bool) :
    evalLinA n m u A =
      xorSumAux (fun x =>
        if hx : x < n * m then
          u ⟨x, hx⟩ && A ⟨x / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩ ⟨x % m, Nat.mod_lt x hm⟩
        else false) (n * m) := by
  rw [xorSumAux_mul]
  unfold evalLinA xorSum
  apply xorSumAux_congr
  intro i hi
  simp only [hi, dite_true]
  apply xorSumAux_congr
  intro j hj
  have hlt : m * i + j < n * m := idx_mul_add_lt hi hj
  have hdiv : (m * i + j) / m = i := by
    rw [Nat.mul_add_div hm, Nat.div_eq_of_lt hj, Nat.add_zero]
  have hmod : (m * i + j) % m = j := by
    rw [Nat.mul_add_mod, Nat.mod_eq_of_lt hj]
  simp only [hj, hlt, dite_true]
  congr 1
  congr 1
  · exact Fin.ext hdiv.symm
  · exact Fin.ext hmod.symm

private theorem evalLinB_eq_flat (m p : Nat) (hp : 0 < p)
    (v : Fin (m * p) → Bool) (B : Fin m → Fin p → Bool) :
    evalLinB m p v B =
      xorSumAux (fun y =>
        if hy : y < m * p then
          v ⟨y, hy⟩ && B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩ ⟨y % p, Nat.mod_lt y hp⟩
        else false) (m * p) := by
  rw [xorSumAux_mul]
  unfold evalLinB xorSum
  apply xorSumAux_congr
  intro j hj
  simp only [hj, dite_true]
  apply xorSumAux_congr
  intro k hk
  have hlt : p * j + k < m * p := idx_mul_add_lt hj hk
  have hdiv : (p * j + k) / p = j := by
    rw [Nat.mul_add_div hp, Nat.div_eq_of_lt hk, Nat.add_zero]
  have hmod : (p * j + k) % p = k := by
    rw [Nat.mul_add_mod, Nat.mod_eq_of_lt hk]
  simp only [hk, hlt, dite_true]
  congr 1
  congr 1
  · exact Fin.ext hdiv.symm
  · exact Fin.ext hmod.symm

/-- **Bilinear Correctness Soundness Theorem**:
Any rank-`r` tensor decomposition `RankLE n m p r` (for `n, m, p > 0`) yields an exact
`r`-product bilinear algorithm computing `matMulF2 n m p A B` for all matrices `A` and `B`. -/
theorem bilinear_of_rankLE {n m p r : Nat} (hn : 0 < n) (hm : 0 < m) (hp : 0 < p)
    (hr : RankLE n m p r) :
    ∃ (a : Fin r → Fin (n * m) → Bool)
      (b : Fin r → Fin (m * p) → Bool)
      (c : Fin r → Fin (p * n) → Bool),
      ∀ (A : Fin n → Fin m → Bool) (B : Fin m → Fin p → Bool) (i : Fin n) (k : Fin p),
        xorSum r (fun s =>
          evalLinA n m (a s) A && evalLinB m p (b s) B &&
          c s ⟨n * k.val + i.val, idx_mul_add_lt k.isLt i.isLt⟩) =
        matMulF2 n m p A B i k := by
  rcases hr with ⟨a, b, c, hrank⟩
  refine ⟨a, b, c, fun A B i k => ?_⟩
  let z : Fin (p * n) := ⟨n * k.val + i.val, idx_mul_add_lt k.isLt i.isLt⟩
  have hzn : z.val / n = k.val := by
    show (n * k.val + i.val) / n = k.val
    rw [Nat.mul_add_div hn, Nat.div_eq_of_lt i.isLt, Nat.add_zero]
  have hzm : z.val % n = i.val := by
    show (n * k.val + i.val) % n = i.val
    rw [Nat.mul_add_mod, Nat.mod_eq_of_lt i.isLt]
  -- Expand `evalLinA`, `evalLinB`, and swap the outer `r`-sum inside `x` and `y`.
  have h1 :
      xorSum r (fun s => evalLinA n m (a s) A && evalLinB m p (b s) B && c s z) =
      xorSumAux (fun s =>
        xorSumAux (fun x =>
          xorSumAux (fun y =>
            if hs : s < r then
              if hx : x < n * m then
                if hy : y < m * p then
                  (a ⟨s, hs⟩ ⟨x, hx⟩ && b ⟨s, hs⟩ ⟨y, hy⟩ && c ⟨s, hs⟩ z) &&
                  (A ⟨x / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩ ⟨x % m, Nat.mod_lt x hm⟩ &&
                   B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩ ⟨y % p, Nat.mod_lt y hp⟩)
                else false
              else false
            else false) (m * p)) (n * m)) r := by
    unfold xorSum
    apply xorSumAux_congr
    intro s hs
    simp only [hs, dite_true, evalLinA_eq_flat n m hm, evalLinB_eq_flat m p hp]
    rw [xorSumAux_and_left, xorSumAux_and_left]
    apply xorSumAux_congr
    intro x hx
    simp only [hx, dite_true]
    rw [Bool.and_assoc, Bool.and_comm _ (c ⟨s, hs⟩ z), ← Bool.and_assoc, xorSumAux_and_right]
    apply xorSumAux_congr
    intro y hy
    simp only [hy, dite_true]
    cases a ⟨s, hs⟩ ⟨x, hx⟩ <;>
      cases A ⟨x / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩ ⟨x % m, Nat.mod_lt x hm⟩ <;>
      cases b ⟨s, hs⟩ ⟨y, hy⟩ <;>
      cases B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩ ⟨y % p, Nat.mod_lt y hp⟩ <;>
      cases c ⟨s, hs⟩ z <;> rfl
  rw [h1, xorSumAux_swap]
  have h2 :
      xorSumAux (fun x =>
        xorSumAux (fun s =>
          xorSumAux (fun y =>
            if hs : s < r then
              if hx : x < n * m then
                if hy : y < m * p then
                  (a ⟨s, hs⟩ ⟨x, hx⟩ && b ⟨s, hs⟩ ⟨y, hy⟩ && c ⟨s, hs⟩ z) &&
                  (A ⟨x / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩ ⟨x % m, Nat.mod_lt x hm⟩ &&
                   B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩ ⟨y % p, Nat.mod_lt y hp⟩)
                else false
              else false
            else false) (m * p)) r) (n * m) =
      xorSumAux (fun x =>
        xorSumAux (fun y =>
          if hx : x < n * m then
            if hy : y < m * p then
              mmT n m p ⟨x, hx⟩ ⟨y, hy⟩ z &&
              (A ⟨x / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩ ⟨x % m, Nat.mod_lt x hm⟩ &&
               B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩ ⟨y % p, Nat.mod_lt y hp⟩)
            else false
          else false) (m * p)) (n * m) := by
    apply xorSumAux_congr
    intro x hx
    rw [xorSumAux_swap]
    apply xorSumAux_congr
    intro y hy
    simp only [hx, hy, dite_true]
    have hpull := (xorSumAux_and_left
      (fun s => if hs : s < r then a ⟨s, hs⟩ ⟨x, hx⟩ && b ⟨s, hs⟩ ⟨y, hy⟩ && c ⟨s, hs⟩ z else false)
      (A ⟨x / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩ ⟨x % m, Nat.mod_lt x hm⟩ &&
       B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩ ⟨y % p, Nat.mod_lt y hp⟩) r).symm
    have hinner :
        xorSumAux (fun s =>
          if hs : s < r then
            (a ⟨s, hs⟩ ⟨x, hx⟩ && b ⟨s, hs⟩ ⟨y, hy⟩ && c ⟨s, hs⟩ z) &&
            (A ⟨x / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩ ⟨x % m, Nat.mod_lt x hm⟩ &&
             B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩ ⟨y % p, Nat.mod_lt y hp⟩)
          else false) r =
        xorSumAux (fun s =>
          (if hs : s < r then a ⟨s, hs⟩ ⟨x, hx⟩ && b ⟨s, hs⟩ ⟨y, hy⟩ && c ⟨s, hs⟩ z else false) &&
          (A ⟨x / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩ ⟨x % m, Nat.mod_lt x hm⟩ &&
           B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩ ⟨y % p, Nat.mod_lt y hp⟩)) r := by
      apply xorSumAux_congr
      intro s hs
      simp [hs]
    rw [hinner, hpull]
    have hbrent := hrank ⟨x, hx⟩ ⟨y, hy⟩ z
    unfold xorSum at hbrent
    rw [hbrent]
  rw [h2, xorSumAux_mul]
  -- Split `x = m * i' + j'` and `y = p * j'' + k'`; only `i' = i`, `j'' = j'`, `k' = k` survive.
  have hsplit :
      xorSumAux (fun i' => xorSumAux (fun j' =>
        xorSumAux (fun y =>
          if hx : m * i' + j' < n * m then
            if hy : y < m * p then
              mmT n m p ⟨m * i' + j', hx⟩ ⟨y, hy⟩ z &&
              (A ⟨(m * i' + j') / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩
                 ⟨(m * i' + j') % m, Nat.mod_lt _ hm⟩ &&
               B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩
                 ⟨y % p, Nat.mod_lt y hp⟩)
            else false
          else false) (m * p)) m) n =
      xorSumAux (fun i' =>
        if i' = i.val then
          xorSumAux (fun j' => if hj' : j' < m then A i ⟨j', hj'⟩ && B ⟨j', hj'⟩ k else false) m
        else false) n := by
    apply xorSumAux_congr
    intro i' hi'
    by_cases hii : i' = i.val
    · subst hii
      simp only [ite_true]
      apply xorSumAux_congr
      intro j' hj'
      have hx : m * i.val + j' < n * m := idx_mul_add_lt i.isLt hj'
      have hdx : (m * i.val + j') / m = i.val := by
        rw [Nat.mul_add_div hm, Nat.div_eq_of_lt hj', Nat.add_zero]
      have hmx : (m * i.val + j') % m = j' := by
        rw [Nat.mul_add_mod, Nat.mod_eq_of_lt hj']
      rw [xorSumAux_mul]
      have hy1 :
          xorSumAux (fun j'' => xorSumAux (fun k' =>
            if hx' : m * i.val + j' < n * m then
              if hy : p * j'' + k' < m * p then
                mmT n m p ⟨m * i.val + j', hx'⟩ ⟨p * j'' + k', hy⟩ z &&
                (A ⟨(m * i.val + j') / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx')⟩
                   ⟨(m * i.val + j') % m, Nat.mod_lt _ hm⟩ &&
                 B ⟨(p * j'' + k') / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩
                   ⟨(p * j'' + k') % p, Nat.mod_lt _ hp⟩)
              else false
            else false) p) m =
          xorSumAux (fun j'' =>
            if j'' = j' then
              xorSumAux (fun k' => if k' = k.val then A i ⟨j', hj'⟩ && B ⟨j', hj'⟩ k else false) p
            else false) m := by
        apply xorSumAux_congr
        intro j'' hj''
        by_cases hjj : j'' = j'
        · subst hjj
          simp only [ite_true]
          apply xorSumAux_congr
          intro k' hk'
          have hy : p * j'' + k' < m * p := idx_mul_add_lt hj'' hk'
          have hdy : (p * j'' + k') / p = j'' := by
            rw [Nat.mul_add_div hp, Nat.div_eq_of_lt hk', Nat.add_zero]
          have hmy : (p * j'' + k') % p = k' := by
            rw [Nat.mul_add_mod, Nat.mod_eq_of_lt hk']
          simp only [hx, hy, dite_true, mmT, hdx, hmx, hdy, hmy, hzn, hzm]
          by_cases hkk : k' = k.val
          · subst hkk
            simp only [ite_true, decide_true, Bool.true_and, and_self]
          · simp [hkk]
        · simp only [hjj, ite_false]
          have hzero :
              xorSumAux (fun k' =>
                if hx' : m * i.val + j' < n * m then
                  if hy : p * j'' + k' < m * p then
                    mmT n m p ⟨m * i.val + j', hx'⟩ ⟨p * j'' + k', hy⟩ z &&
                    (A ⟨(m * i.val + j') / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx')⟩
                       ⟨(m * i.val + j') % m, Nat.mod_lt _ hm⟩ &&
                     B ⟨(p * j'' + k') / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩
                       ⟨(p * j'' + k') % p, Nat.mod_lt _ hp⟩)
                  else false
                else false) p = xorSumAux (fun _ => false) p := by
            apply xorSumAux_congr
            intro k' hk'
            have hy : p * j'' + k' < m * p := idx_mul_add_lt hj'' hk'
            have hdy : (p * j'' + k') / p = j'' := by
              rw [Nat.mul_add_div hp, Nat.div_eq_of_lt hk', Nat.add_zero]
            have hne : j' ≠ j'' := fun h => hjj h.symm
            simp [hx, hy, mmT, hmx, hdy, hne]
          rw [hzero, xorSumAux_false]
      rw [hy1, xorSumAux_single j' _ m]
      simp only [hj', ite_true, dite_true]
      rw [xorSumAux_single k.val _ p]
      simp [k.isLt]
    · simp only [hii, ite_false]
      have hzero :
          xorSumAux (fun j' =>
            xorSumAux (fun y =>
              if hx : m * i' + j' < n * m then
                if hy : y < m * p then
                  mmT n m p ⟨m * i' + j', hx⟩ ⟨y, hy⟩ z &&
                  (A ⟨(m * i' + j') / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx)⟩
                     ⟨(m * i' + j') % m, Nat.mod_lt _ hm⟩ &&
                   B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩
                     ⟨y % p, Nat.mod_lt y hp⟩)
                else false
              else false) (m * p)) m = xorSumAux (fun _ => false) m := by
        apply xorSumAux_congr
        intro j' hj'
        have hx : m * i' + j' < n * m := idx_mul_add_lt hi' hj'
        have hdx : (m * i' + j') / m = i' := by
          rw [Nat.mul_add_div hm, Nat.div_eq_of_lt hj', Nat.add_zero]
        have hne : i.val ≠ i' := fun h => hii h.symm
        have hyz :
            xorSumAux (fun y =>
              if hx' : m * i' + j' < n * m then
                if hy : y < m * p then
                  mmT n m p ⟨m * i' + j', hx'⟩ ⟨y, hy⟩ z &&
                  (A ⟨(m * i' + j') / m, Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ hx')⟩
                     ⟨(m * i' + j') % m, Nat.mod_lt _ hm⟩ &&
                   B ⟨y / p, Nat.div_lt_of_lt_mul (Nat.mul_comm m p ▸ hy)⟩
                     ⟨y % p, Nat.mod_lt y hp⟩)
                else false
              else false) (m * p) = xorSumAux (fun _ => false) (m * p) := by
          apply xorSumAux_congr
          intro y hy
          simp [hx, hy, mmT, hdx, hzm, hne]
        rw [hyz, xorSumAux_false]
      rw [hzero, xorSumAux_false]
  rw [hsplit, xorSumAux_single i.val _ n]
  simp only [i.isLt, ite_true]
  rfl

/-! ## Ultra-Fast Bit-Packed Brent-Equation Kernel Verifier -/

/-- Filter mask triples `(a, b, c)` retaining `(b, c)` whenever `a.testBit x = true`. -/
def filterX (x : Nat) : List (Nat × Nat × Nat) → List (Nat × Nat)
  | [] => []
  | (a, b, c) :: rest => if a.testBit x then (b, c) :: filterX x rest else filterX x rest

/-- XOR-accumulate `c` across all `(b, c)` in `sub` where `b.testBit y = true`. -/
def xorCForY (y : Nat) : List (Nat × Nat) → Nat → Nat
  | [], acc => acc
  | (b, c) :: rest, acc =>
    let acc' := if b.testBit y then acc ^^^ c else acc
    xorCForY y rest acc'

/-- Target bitmask over `z < p * n` for fixed `(x, y)`:
bit `n * (y % p) + x / m` is set iff `x % m == y / p`, else `0`. -/
def tgtMaskXY (n m p x y : Nat) : Nat :=
  if x % m == y / p then 1 <<< (n * (y % p) + x / m) else 0

/-- Check all `y < k` for a fixed `x`, using the pre-filtered list `Lx` and `maskZ = 2^(p*n) - 1`. -/
def checkForXAux (n m p x maskZ : Nat) (Lx : List (Nat × Nat)) : Nat → Bool
  | 0 => true
  | y + 1 =>
    (((xorCForY y Lx 0) &&& maskZ) == tgtMaskXY n m p x y) &&
      checkForXAux n m p x maskZ Lx y

/-- Check all `x < k` and `y < m * p` (and all `z < p * n` simultaneously via bitmasks). -/
def checkBrentF2Aux (n m p maskZ : Nat) (L : List (Nat × Nat × Nat)) : Nat → Bool
  | 0 => true
  | x + 1 =>
    checkForXAux n m p x maskZ (filterX x L) (m * p) &&
      checkBrentF2Aux n m p maskZ L x

/-- Single-pass bit-packed Brent-equation checker for a certificate list `L` of `(a, b, c)` masks. -/
def checkBrentF2 (n m p : Nat) (L : List (Nat × Nat × Nat)) : Bool :=
  if n == 0 || m == 0 || p == 0 then false
  else
    let maskZ := (1 <<< (p * n)) - 1
    checkBrentF2Aux n m p maskZ L (n * m)

private def listParityBC (y z : Nat) : List (Nat × Nat) → Bool
  | [] => false
  | (b, c) :: rest => xor (b.testBit y && c.testBit z) (listParityBC y z rest)

private def listParityABC (x y z : Nat) : List (Nat × Nat × Nat) → Bool
  | [] => false
  | (a, b, c) :: rest =>
    xor (a.testBit x && b.testBit y && c.testBit z) (listParityABC x y z rest)

private theorem xorCForY_testBit (y z : Nat) :
    ∀ (sub : List (Nat × Nat)) (acc : Nat),
      (xorCForY y sub acc).testBit z = xor (acc.testBit z) (listParityBC y z sub)
  | [], acc => by simp [xorCForY, listParityBC]
  | (b, c) :: rest, acc => by
    simp only [xorCForY, listParityBC]
    rw [xorCForY_testBit y z rest]
    cases hb : b.testBit y
    · simp
    · simp only [ite_true, Bool.true_and]
      rw [Nat.testBit_xor]
      exact xor_assoc_b _ _ _

private theorem listParityBC_filterX (x y z : Nat) :
    ∀ (L : List (Nat × Nat × Nat)),
      listParityBC y z (filterX x L) = listParityABC x y z L
  | [] => rfl
  | (a, b, c) :: rest => by
    simp only [filterX, listParityABC]
    cases ha : a.testBit x
    · simp [listParityBC_filterX x y z rest]
    · simp [listParityBC, listParityBC_filterX x y z rest]

private theorem xorSumAux_cons_list {α : Type} (g : α → Bool) (d : α) (t : α) (L : List α) :
    ∀ k, k ≤ L.length →
      xorSumAux (fun s => g ((t :: L).getD s d)) (k + 1) =
        xor (g t) (xorSumAux (fun s => g (L.getD s d)) k)
  | 0, _ => by simp [xorSumAux, List.getD]
  | k + 1, hk => by
    have hstep := xorSumAux_cons_list g d t L k (by omega)
    rw [xorSumAux, hstep, List.getD_cons_succ, xorSumAux, xor_assoc_b]

private theorem listParityABC_eq_xorSumAux (L : List (Nat × Nat × Nat)) (x y z : Nat) :
    listParityABC x y z L =
      xorSumAux (fun s =>
        let t := L.getD s (0, 0, 0)
        t.1.testBit x && t.2.1.testBit y && t.2.2.testBit z) L.length := by
  induction L with
  | nil => rfl
  | cons hd tl ih =>
    rcases hd with ⟨a, b, c⟩
    simp only [listParityABC, List.length_cons]
    rw [xorSumAux_cons_list (fun t : Nat × Nat × Nat => t.1.testBit x && t.2.1.testBit y && t.2.2.testBit z)
      (0, 0, 0) (a, b, c) tl tl.length (Nat.le_refl _)]
    rw [ih]

private theorem listParityABC_eq_xorSum (L : List (Nat × Nat × Nat)) (x y z : Nat) :
    listParityABC x y z L =
      xorSum L.length (fun s =>
        let t := L.getD s.val (0, 0, 0)
        t.1.testBit x && t.2.1.testBit y && t.2.2.testBit z) := by
  rw [listParityABC_eq_xorSumAux]
  unfold xorSum
  apply xorSumAux_congr
  intro i hi
  simp [hi]

private theorem checkForXAux_sound (n m p x maskZ : Nat) (Lx : List (Nat × Nat)) :
    ∀ k, checkForXAux n m p x maskZ Lx k = true →
      ∀ y, y < k → ((xorCForY y Lx 0) &&& maskZ) = tgtMaskXY n m p x y
  | 0, _, _, hy => by omega
  | k + 1, h, y, hy => by
    simp only [checkForXAux, Bool.and_eq_true, beq_iff_eq] at h
    by_cases hlt : y < k
    · exact checkForXAux_sound n m p x maskZ Lx k h.2 y hlt
    · have heq : y = k := by omega
      subst heq
      exact h.1

private theorem checkBrentF2Aux_sound (n m p maskZ : Nat) (L : List (Nat × Nat × Nat)) :
    ∀ k, checkBrentF2Aux n m p maskZ L k = true →
      ∀ x, x < k → ∀ y, y < m * p →
        ((xorCForY y (filterX x L) 0) &&& maskZ) = tgtMaskXY n m p x y
  | 0, _, _, hx, _, _ => by omega
  | k + 1, h, x, hx, y, hy => by
    simp only [checkBrentF2Aux, Bool.and_eq_true] at h
    by_cases hlt : x < k
    · exact checkBrentF2Aux_sound n m p maskZ L k h.2 x hlt y hy
    · have heq : x = k := by omega
      subst heq
      exact checkForXAux_sound n m p x maskZ (filterX x L) (m * p) h.1 y hy

private theorem maskZ_testBit (acc k z : Nat) (hz : z < k) :
    (acc &&& ((1 <<< k) - 1)).testBit z = acc.testBit z := by
  have hpow : 1 <<< k = 2 ^ k := by simp [Nat.shiftLeft_eq]
  rw [hpow, Nat.and_two_pow_sub_one_eq_mod, Nat.testBit_mod_two_pow]
  simp [hz]

private theorem tgtMaskXY_testBit (n m p : Nat) (hn : 0 < n) (_hm : 0 < m) (_hp : 0 < p)
    (x : Fin (n * m)) (y : Fin (m * p)) (z : Fin (p * n)) :
    (tgtMaskXY n m p x.val y.val).testBit z.val = mmT n m p x y z := by
  unfold tgtMaskXY mmT
  by_cases h1 : x.val % m = y.val / p
  · simp only [h1, beq_self_eq_true, ite_true]
    have hpow : 1 <<< (n * (y.val % p) + x.val / m) = 2 ^ (n * (y.val % p) + x.val / m) := by
      simp [Nat.shiftLeft_eq]
    rw [hpow, Nat.testBit_two_pow]
    have hxm_lt : x.val / m < n := Nat.div_lt_of_lt_mul (Nat.mul_comm n m ▸ x.isLt)
    have heq_iff : (n * (y.val % p) + x.val / m = z.val) ↔ (y.val % p = z.val / n ∧ z.val % n = x.val / m) := by
      constructor
      · intro h
        rw [← h]
        constructor
        · rw [Nat.mul_add_div hn, Nat.div_eq_of_lt hxm_lt, Nat.add_zero]
        · rw [Nat.mul_add_mod, Nat.mod_eq_of_lt hxm_lt]
      · intro ⟨hdiv, hmod⟩
        rw [hdiv, ← hmod]
        exact Nat.div_add_mod z.val n
    by_cases hcond : n * (y.val % p) + x.val / m = z.val
    · have hpair := heq_iff.mp hcond
      rw [decide_eq_true hcond, decide_eq_true ⟨trivial, hpair.1, hpair.2⟩]
    · have hnpair : ¬ (True ∧ y.val % p = z.val / n ∧ z.val % n = x.val / m) :=
        fun ⟨_, hp1, hp2⟩ => hcond (heq_iff.mpr ⟨hp1, hp2⟩)
      rw [decide_eq_false hcond, decide_eq_false hnpair]
  · simp [h1]

/-- **Bit-Packed Certificate Soundness Theorem**:
If `L.length = r` and `checkBrentF2 n m p L = true`, then `RankLE n m p r`. -/
theorem rankLE_of_checkBrentF2 (n m p : Nat) (L : List (Nat × Nat × Nat)) {r : Nat}
    (hlen : L.length = r) (hcheck : checkBrentF2 n m p L = true) :
    RankLE n m p r := by
  unfold checkBrentF2 at hcheck
  by_cases hzero : (n == 0 || m == 0 || p == 0) = true
  · simp [hzero] at hcheck
  · simp only [hzero, Bool.false_eq_true, ite_false] at hcheck
    have hn : 0 < n := by
      cases n with
      | zero => simp at hzero
      | succ _ => exact Nat.zero_lt_succ _
    have hm : 0 < m := by
      cases m with
      | zero => simp at hzero
      | succ _ => exact Nat.zero_lt_succ _
    have hp : 0 < p := by
      cases p with
      | zero => simp at hzero
      | succ _ => exact Nat.zero_lt_succ _
    subst hlen
    refine ⟨fun s x => (L.getD s.val (0, 0, 0)).1.testBit x.val,
      fun s y => (L.getD s.val (0, 0, 0)).2.1.testBit y.val,
      fun s z => (L.getD s.val (0, 0, 0)).2.2.testBit z.val, ?_⟩
    intro x y z
    have hxy := checkBrentF2Aux_sound n m p ((1 <<< (p * n)) - 1) L (n * m) hcheck x.val x.isLt y.val y.isLt
    have hbit := congrArg (fun v => v.testBit z.val) hxy
    rw [maskZ_testBit _ (p * n) z.val z.isLt, xorCForY_testBit, Nat.zero_testBit, Bool.false_xor,
      listParityBC_filterX, listParityABC_eq_xorSum, tgtMaskXY_testBit n m p hn hm hp x y z] at hbit
    exact hbit

end RankF2Ext
