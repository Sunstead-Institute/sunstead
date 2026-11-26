/-!
# Binary Error-Correcting Codes & Constant-Weight Codes: Formal Specification and Kernel Evaluator

This module formalizes binary block codes `A(n, d)` and binary constant-weight codes
`A(n, d, w)` in pure Lean 4.36.0 (zero Mathlib, standard axioms only):

1. Semantic length-`n` binary vectors (`Fin n → Bool`), Hamming weight (`hammingWeight`),
   and Hamming distance (`hammingDist`).
2. Target predicates `ValidBinaryCode n d M` (certifying `A(n, d) ≥ M`) and
   `ValidConstantWeightCode n d w M` (certifying `A(n, d, w) ≥ M`), explicitly requiring
   all `M` codewords to be pairwise distinct (`C.get i ≠ C.get j`) with pairwise Hamming
   distance `≥ d` (and exact weight `w` for constant-weight codes).
3. A fast 32-bit carry-free SWAR kernel popcount (`popcount32`) and pairwise distance checker
   (`checkBounds`, `checkWeights`, `checkAllDist`) with complete sorry-free soundness proofs
   (`validBinaryCode_of_check`, `validConstantWeightCode_of_check`).

Upstream benchmark records and constant-weight code lower bounds are pinned to
`williamechols/cwc-seeded-tabu-search` at commit `4f0bf18b094fb15c3634001ea8aed847e8353d1c` (MIT),
building on Christopher D. Rosin's `CWBC` (arXiv:2603.00174) and A. E. Brouwer's tables for
`A(n, d)` and `A(n, d, w)`.
-/

namespace CodingBounds

/-! ## Semantic binary vectors, Hamming weight, and Hamming distance -/

/-- Number of `true` coordinates among indices `0, ..., k - 1` of `v : Fin n → Bool`. -/
def hammingWeightAux {n : Nat} (v : Fin n → Bool) : (k : Nat) → k ≤ n → Nat
  | 0, _ => 0
  | k + 1, hk =>
    hammingWeightAux v k (Nat.le_of_succ_le hk) + (if v ⟨k, hk⟩ then 1 else 0)

/-- Hamming weight of a binary vector `v : Fin n → Bool`. -/
def hammingWeight (n : Nat) (v : Fin n → Bool) : Nat :=
  hammingWeightAux v n (Nat.le_refl n)

/-- Hamming distance between two binary vectors `u, v : Fin n → Bool`. -/
def hammingDist (n : Nat) (u v : Fin n → Bool) : Nat :=
  hammingWeight n (fun i => xor (u i) (v i))

theorem hammingWeightAux_congr {n : Nat} {u v : Fin n → Bool}
    (h : ∀ i, u i = v i) (k : Nat) (hk : k ≤ n) :
    hammingWeightAux u k hk = hammingWeightAux v k hk := by
  induction k with
  | zero => rfl
  | succ k ih =>
    simp only [hammingWeightAux, ih (Nat.le_of_succ_le hk), h]

theorem hammingDist_symm (n : Nat) (u v : Fin n → Bool) :
    hammingDist n u v = hammingDist n v u := by
  unfold hammingDist hammingWeight
  apply hammingWeightAux_congr
  intro i
  cases u i <;> cases v i <;> rfl

/-! ## Mission target predicates -/

/-- Existence of a binary code of length `n`, minimum Hamming distance `≥ d`, and size `M`
(certifying `A(n, d) ≥ M`). Every pair of distinct indices has distinct codewords at
Hamming distance at least `d`. -/
def ValidBinaryCode (n d M : Nat) : Prop :=
  ∃ C : List (Fin n → Bool),
    C.length = M ∧
    ∀ i j : Fin C.length, i ≠ j →
      C.get i ≠ C.get j ∧ d ≤ hammingDist n (C.get i) (C.get j)

/-- Existence of a binary constant-weight code of length `n`, minimum Hamming distance `≥ d`,
constant Hamming weight `w`, and size `M` (certifying `A(n, d, w) ≥ M`). -/
def ValidConstantWeightCode (n d w M : Nat) : Prop :=
  ∃ C : List (Fin n → Bool),
    C.length = M ∧
    (∀ i : Fin C.length, hammingWeight n (C.get i) = w) ∧
    ∀ i j : Fin C.length, i ≠ j →
      C.get i ≠ C.get j ∧ d ≤ hammingDist n (C.get i) (C.get j)

/-! ## Bit-vector decoding and fast SWAR popcount evaluator -/

/-- Decode a natural number `x` into a length-`n` binary vector via its low `n` bits. -/
def wordVec (n : Nat) (x : Nat) : Fin n → Bool :=
  fun i => x.testBit i.val

/-- Pure 8-bit SWAR popcount (exact for `x < 256`). -/
def popcount8 (x : Nat) : Nat :=
  let a := (x &&& 0x55) + ((x >>> 1) &&& 0x55)
  let b := (a &&& 0x33) + ((a >>> 2) &&& 0x33)
  (b &&& 0x0f) + ((b >>> 4) &&& 0x0f)

/-- Pure 32-bit carry-free SWAR popcount (exact for all `x < 2^32`). -/
def popcount32 (x : Nat) : Nat :=
  let a := (x &&& 0x55555555) + ((x >>> 1) &&& 0x55555555)
  let b := (a &&& 0x33333333) + ((a >>> 2) &&& 0x33333333)
  let c := (b &&& 0x0f0f0f0f) + ((b >>> 4) &&& 0x0f0f0f0f)
  let d := (c &&& 0x00ff00ff) + ((c >>> 8) &&& 0x00ff00ff)
  (d &&& 0x0000ffff) + ((d >>> 16) &&& 0x0000ffff)

/-- Check that every codeword satisfies `x < bound`. -/
def checkBounds (bound : Nat) : List Nat → Bool
  | [] => true
  | x :: xs => Nat.blt x bound && checkBounds bound xs

/-- Check that every codeword has `popcount32 x == w`. -/
def checkWeights (w : Nat) : List Nat → Bool
  | [] => true
  | x :: xs => (popcount32 x == w) && checkWeights w xs

/-- Check that `x` is distinct from and at Hamming distance `≥ d` from every word in `ys`. -/
def checkDistAgainst (d x : Nat) : List Nat → Bool
  | [] => true
  | y :: ys =>
    (x != y) && Nat.ble d (popcount32 (x ^^^ y)) && checkDistAgainst d x ys

/-- Check that all distinct pairs in `words` are distinct and have Hamming distance `≥ d`. -/
def checkAllDist (d : Nat) : List Nat → Bool
  | [] => true
  | x :: xs => checkDistAgainst d x xs && checkAllDist d xs

/-! ## Soundness proofs -/

/-- Reference recursive bit-count over the low `k` bits of `x`. -/
def bitWeight (x : Nat) : Nat → Nat
  | 0 => 0
  | k + 1 => bitWeight x k + (if x.testBit k then 1 else 0)

theorem hammingWeightAux_wordVec (n x : Nat) (k : Nat) (hk : k ≤ n) :
    hammingWeightAux (wordVec n x) k hk = bitWeight x k := by
  induction k with
  | zero => rfl
  | succ k ih =>
    rw [hammingWeightAux, bitWeight, ih (Nat.le_of_succ_le hk)]
    rfl

theorem hammingWeight_wordVec (n x : Nat) :
    hammingWeight n (wordVec n x) = bitWeight x n :=
  hammingWeightAux_wordVec n x n (Nat.le_refl n)

theorem bitWeight_eq_of_lt_two_pow (x n k : Nat) (hnk : n ≤ k) (hx : x < 2 ^ n) :
    bitWeight x k = bitWeight x n := by
  induction k with
  | zero =>
    have hn0 : n = 0 := by omega
    subst hn0; rfl
  | succ k ih =>
    by_cases h : n ≤ k
    · have hzero : x.testBit k = false := by
        apply Nat.testBit_lt_two_pow
        exact Nat.lt_of_lt_of_le hx (Nat.pow_le_pow_right (by omega) h)
      simp only [bitWeight, hzero, Bool.false_eq_true, ↓reduceIte, Nat.add_zero]
      exact ih h
    · have hnk' : n = k + 1 := by omega
      subst hnk'; rfl

theorem bitWeight_add_shift (x a b : Nat) :
    bitWeight x (a + b) = bitWeight x a + bitWeight (x >>> a) b := by
  induction b with
  | zero => simp [bitWeight]
  | succ b ih =>
    rw [← Nat.add_assoc]
    simp only [bitWeight, Nat.testBit_shiftRight]
    rw [ih, Nat.add_assoc]

theorem bitWeight_mod_two_pow (x k : Nat) :
    bitWeight (x &&& ((1 <<< k) - 1)) k = bitWeight x k := by
  have h1 : (1 <<< k) = 2 ^ k := by rw [Nat.shiftLeft_eq, Nat.one_mul]
  rw [h1]
  have aux : ∀ j, j ≤ k → bitWeight (x &&& (2 ^ k - 1)) j = bitWeight x j := by
    intro j hj
    induction j with
    | zero => rfl
    | succ j ih =>
      rw [bitWeight, bitWeight, ih (Nat.le_of_succ_le hj), Nat.testBit_and, Nat.testBit_two_pow_sub_one]
      have hjk : j < k := by omega
      simp [hjk]
  exact aux k (Nat.le_refl k)

theorem bitWeight_32_bytes (x : Nat) :
    bitWeight x 32 =
      bitWeight (x &&& 0xff) 8 +
      bitWeight ((x >>> 8) &&& 0xff) 8 +
      bitWeight ((x >>> 16) &&& 0xff) 8 +
      bitWeight ((x >>> 24) &&& 0xff) 8 := by
  have h8 : (0xff : Nat) = (1 <<< 8) - 1 := by decide
  rw [h8]
  simp only [bitWeight_mod_two_pow]
  have h1 : bitWeight x 32 = bitWeight x 24 + bitWeight (x >>> 24) 8 :=
    bitWeight_add_shift x 24 8
  have h2 : bitWeight x 24 = bitWeight x 16 + bitWeight (x >>> 16) 8 :=
    bitWeight_add_shift x 16 8
  have h3 : bitWeight x 16 = bitWeight x 8 + bitWeight (x >>> 8) 8 :=
    bitWeight_add_shift x 8 8
  omega

/-- Exhaustive kernel verification of `popcount8` on all 256 byte values. -/
theorem popcount8_eq_bitWeight_fin :
    ∀ b : Fin 256, popcount8 b.val = bitWeight b.val 8 := by
  decide +kernel

theorem popcount8_eq_bitWeight (x : Nat) (hx : x < 256) :
    popcount8 x = bitWeight x 8 :=
  popcount8_eq_bitWeight_fin ⟨x, hx⟩

theorem popcount8_le_8 (x : Nat) (hx : x < 256) : popcount8 x ≤ 8 := by
  have h : ∀ b : Fin 256, popcount8 b.val ≤ 8 := by decide +kernel
  exact h ⟨x, hx⟩

private theorem byte_lt_256 (x : Nat) : (x &&& 0xff) < 256 := by
  have h : (0xff : Nat) = 2 ^ 8 - 1 := by decide
  rw [h, Nat.and_two_pow_sub_one_eq_mod]
  exact Nat.mod_lt x (by decide)

private theorem testBit_add_mul_256 (p q j : Nat) (hp : p < 256) :
    (p + 256 * q).testBit j = if j < 8 then p.testBit j else q.testBit (j - 8) := by
  by_cases hj : j < 8
  · simp only [hj, ↓reduceIte]
    rw [Nat.testBit_eq_decide_div_mod_eq, Nat.testBit_eq_decide_div_mod_eq]
    have h256 : 256 = 2 ^ j * 2 ^ (8 - j) := by
      have h8 : (256 : Nat) = 2 ^ 8 := by decide
      rw [h8, ← Nat.pow_add]
      congr 1; omega
    have hd : (p + 256 * q) / 2 ^ j = p / 2 ^ j + 2 ^ (8 - j) * q := by
      rw [h256, Nat.mul_assoc, Nat.add_mul_div_left _ _ (Nat.two_pow_pos j)]
    rw [hd]
    have heven : 2 ∣ 2 ^ (8 - j) := by
      have hsub : 8 - j = (7 - j) + 1 := by omega
      rw [hsub, Nat.pow_succ]
      exact ⟨2 ^ (7 - j), by omega⟩
    rcases heven with ⟨r, hr⟩
    rw [hr, Nat.mul_assoc, Nat.add_mul_mod_self_left]
  · simp only [hj, ↓reduceIte]
    rw [Nat.testBit_eq_decide_div_mod_eq, Nat.testBit_eq_decide_div_mod_eq]
    have hpow : 2 ^ j = 256 * 2 ^ (j - 8) := by
      have h8 : (256 : Nat) = 2 ^ 8 := by decide
      rw [h8, ← Nat.pow_add]
      congr 1; omega
    rw [hpow, ← Nat.div_div_eq_div_mul]
    have hdiv256 : (p + 256 * q) / 256 = q := by
      rw [Nat.add_mul_div_left _ _ (by decide), Nat.div_eq_of_lt hp, Nat.zero_add]
    rw [hdiv256]

private theorem testBit_pack4 (u0 u1 u2 u3 j : Nat)
    (hu0 : u0 < 256) (hu1 : u1 < 256) (hu2 : u2 < 256) (hu3 : u3 < 256) :
    (u0 + 256 * u1 + 65536 * u2 + 16777216 * u3).testBit j =
      if j < 8 then u0.testBit j
      else if j < 16 then u1.testBit (j - 8)
      else if j < 24 then u2.testBit (j - 16)
      else if j < 32 then u3.testBit (j - 24)
      else false := by
  have hl1 : u0 + 256 * u1 + 65536 * u2 + 16777216 * u3 =
      u0 + 256 * (u1 + 256 * (u2 + 256 * u3)) := by omega
  rw [hl1, testBit_add_mul_256 u0 _ j hu0]
  by_cases h1 : j < 8
  · simp [h1]
  · simp only [h1, ↓reduceIte]
    rw [testBit_add_mul_256 u1 _ (j - 8) hu1]
    by_cases h2 : j < 16
    · have h2' : j - 8 < 8 := by omega
      simp [h2, h2']
    · have h2' : ¬ (j - 8 < 8) := by omega
      simp only [h2, h2', ↓reduceIte]
      rw [testBit_add_mul_256 u2 _ (j - 8 - 8) hu2]
      by_cases h3 : j < 24
      · have heq : j - 8 - 8 = j - 16 := by omega
        have h3' : j - 16 < 8 := by omega
        simp [h3, heq, h3']
      · have h3' : ¬ (j - 8 - 8 < 8) := by omega
        simp only [h3, h3', ↓reduceIte]
        by_cases h4 : j < 32
        · have heq : j - 8 - 8 - 8 = j - 24 := by omega
          simp [h4, heq]
        · simp only [h4, ↓reduceIte]
          apply Nat.testBit_lt_two_pow
          have : 256 ≤ 2 ^ (j - 8 - 8 - 8) := by
            have hge : 8 ≤ j - 8 - 8 - 8 := by omega
            exact Nat.le_trans (by decide) (Nat.pow_le_pow_right (by omega) hge)
          omega

private theorem and_pack4_rep (v0 v1 v2 v3 m : Nat)
    (hv0 : v0 < 256) (hv1 : v1 < 256) (hv2 : v2 < 256) (hv3 : v3 < 256) (hm : m < 256) :
    ((v0 + 256 * v1 + 65536 * v2 + 16777216 * v3) &&&
     (m + 256 * m + 65536 * m + 16777216 * m)) =
      (v0 &&& m) + 256 * (v1 &&& m) + 65536 * (v2 &&& m) + 16777216 * (v3 &&& m) := by
  have hand_lt : ∀ u, (u &&& m) < 256 := fun u => by
    have : (u &&& m) ≤ m := Nat.and_le_right
    omega
  apply Nat.eq_of_testBit_eq
  intro i
  rw [Nat.testBit_and,
      testBit_pack4 v0 v1 v2 v3 i hv0 hv1 hv2 hv3,
      testBit_pack4 m m m m i hm hm hm hm,
      testBit_pack4 (v0 &&& m) (v1 &&& m) (v2 &&& m) (v3 &&& m) i
        (hand_lt v0) (hand_lt v1) (hand_lt v2) (hand_lt v3)]
  by_cases h1 : i < 8
  · simp [h1, Nat.testBit_and]
  · by_cases h2 : i < 16
    · simp [h1, h2, Nat.testBit_and]
    · by_cases h3 : i < 24
      · simp [h1, h2, h3, Nat.testBit_and]
      · by_cases h4 : i < 32
        · simp [h1, h2, h3, h4, Nat.testBit_and]
        · simp [h1, h2, h3, h4]

private theorem shift_and_pack4_rep (v0 v1 v2 v3 s m : Nat)
    (hv0 : v0 < 256) (hv1 : v1 < 256) (hv2 : v2 < 256) (hv3 : v3 < 256)
    (hs : s < 8) (hm : m < 2 ^ (8 - s)) :
    (((v0 + 256 * v1 + 65536 * v2 + 16777216 * v3) >>> s) &&&
     (m + 256 * m + 65536 * m + 16777216 * m)) =
      ((v0 >>> s) &&& m) + 256 * ((v1 >>> s) &&& m) +
      65536 * ((v2 >>> s) &&& m) + 16777216 * ((v3 >>> s) &&& m) := by
  have hm256 : m < 256 := by
    have : 2 ^ (8 - s) ≤ 2 ^ 8 := Nat.pow_le_pow_right (by omega) (by omega)
    omega
  have hand_lt : ∀ u, ((u >>> s) &&& m) < 256 := fun u => by
    have : ((u >>> s) &&& m) ≤ m := Nat.and_le_right
    omega
  have hm_hi : ∀ r, 8 - s ≤ r → m.testBit r = false := fun r hr =>
    Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le hm (Nat.pow_le_pow_right (by omega) hr))
  apply Nat.eq_of_testBit_eq
  intro k
  rw [Nat.testBit_and, Nat.testBit_shiftRight,
      testBit_pack4 v0 v1 v2 v3 (s + k) hv0 hv1 hv2 hv3,
      testBit_pack4 m m m m k hm256 hm256 hm256 hm256,
      testBit_pack4 ((v0 >>> s) &&& m) ((v1 >>> s) &&& m) ((v2 >>> s) &&& m) ((v3 >>> s) &&& m) k
        (hand_lt v0) (hand_lt v1) (hand_lt v2) (hand_lt v3)]
  by_cases h1 : k < 8
  · simp only [h1, ↓reduceIte, Nat.testBit_and, Nat.testBit_shiftRight]
    by_cases h1s : s + k < 8
    · simp [h1s]
    · simp [hm_hi k (by omega)]
  · by_cases h2 : k < 16
    · simp only [h1, h2, ↓reduceIte, Nat.testBit_and, Nat.testBit_shiftRight]
      by_cases h2s : s + k < 16
      · have h2l : ¬ (s + k < 8) := by omega
        have heq : s + k - 8 = s + (k - 8) := by omega
        simp [h2l, h2s, heq]
      · simp [hm_hi (k - 8) (by omega)]
    · by_cases h3 : k < 24
      · simp only [h1, h2, h3, ↓reduceIte, Nat.testBit_and, Nat.testBit_shiftRight]
        by_cases h3s : s + k < 24
        · have h3l1 : ¬ (s + k < 8) := by omega
          have h3l2 : ¬ (s + k < 16) := by omega
          have heq : s + k - 16 = s + (k - 16) := by omega
          simp [h3l1, h3l2, h3s, heq]
        · simp [hm_hi (k - 16) (by omega)]
      · by_cases h4 : k < 32
        · simp only [h1, h2, h3, h4, ↓reduceIte, Nat.testBit_and, Nat.testBit_shiftRight]
          by_cases h4s : s + k < 32
          · have h4l1 : ¬ (s + k < 8) := by omega
            have h4l2 : ¬ (s + k < 16) := by omega
            have h4l3 : ¬ (s + k < 24) := by omega
            have heq : s + k - 24 = s + (k - 24) := by omega
            simp [h4l1, h4l2, h4l3, h4s, heq]
          · simp [hm_hi (k - 24) (by omega)]
        · simp [h1, h2, h3, h4]

private theorem and_00ff00ff (u0 u1 u2 u3 : Nat)
    (hu0 : u0 < 256) (hu1 : u1 < 256) (hu2 : u2 < 256) (hu3 : u3 < 256) :
    ((u0 + 256 * u1 + 65536 * u2 + 16777216 * u3) &&& 0x00ff00ff) = u0 + 65536 * u2 := by
  have hm_eq : (0x00ff00ff : Nat) = 0xff + 256 * 0 + 65536 * 0xff + 16777216 * 0 := by decide
  have hr_eq : u0 + 65536 * u2 = u0 + 256 * 0 + 65536 * u2 + 16777216 * 0 := by omega
  have hff : ∀ r, r < 8 → (0xff : Nat).testBit r = true := fun r hr => by
    have : (0xff : Nat) = 2 ^ 8 - 1 := by decide
    rw [this, Nat.testBit_two_pow_sub_one]; simp [hr]
  apply Nat.eq_of_testBit_eq
  intro i
  rw [Nat.testBit_and, hm_eq, hr_eq,
      testBit_pack4 u0 u1 u2 u3 i hu0 hu1 hu2 hu3,
      testBit_pack4 0xff 0 0xff 0 i (by decide) (by decide) (by decide) (by decide),
      testBit_pack4 u0 0 u2 0 i hu0 (by decide) hu2 (by decide)]
  by_cases h1 : i < 8
  · simp [h1, hff i h1]
  · by_cases h2 : i < 16
    · simp [h1, h2]
    · by_cases h3 : i < 24
      · simp [h1, h2, h3, hff (i - 16) (by omega)]
      · by_cases h4 : i < 32
        · simp [h1, h2, h3, h4]
        · simp [h1, h2, h3, h4]

private theorem swar_step_c_bytes (x : Nat) (hx : x < 2 ^ 32) :
    let a := (x &&& 0x55555555) + ((x >>> 1) &&& 0x55555555)
    let b := (a &&& 0x33333333) + ((a >>> 2) &&& 0x33333333)
    let c := (b &&& 0x0f0f0f0f) + ((b >>> 4) &&& 0x0f0f0f0f)
    c = popcount8 (x &&& 0xff) +
        256 * popcount8 ((x >>> 8) &&& 0xff) +
        65536 * popcount8 ((x >>> 16) &&& 0xff) +
        16777216 * popcount8 ((x >>> 24) &&& 0xff) := by
  let x0 := x &&& 0xff
  let x1 := (x >>> 8) &&& 0xff
  let x2 := (x >>> 16) &&& 0xff
  let x3 := (x >>> 24) &&& 0xff
  have hx0 : x0 < 256 := byte_lt_256 x
  have hx1 : x1 < 256 := byte_lt_256 (x >>> 8)
  have hx2 : x2 < 256 := byte_lt_256 (x >>> 16)
  have hx3 : x3 < 256 := byte_lt_256 (x >>> 24)
  have hx_eq : x = x0 + 256 * x1 + 65536 * x2 + 16777216 * x3 := by
    have h0 : x0 = x % 256 := by
      show (x &&& 0xff) = x % 256
      have : (0xff : Nat) = 2 ^ 8 - 1 := by decide
      rw [this, Nat.and_two_pow_sub_one_eq_mod]
    have h1 : x1 = (x / 256) % 256 := by
      show ((x >>> 8) &&& 0xff) = (x / 256) % 256
      have : (0xff : Nat) = 2 ^ 8 - 1 := by decide
      rw [this, Nat.and_two_pow_sub_one_eq_mod, Nat.shiftRight_eq_div_pow]
    have h2 : x2 = (x / 65536) % 256 := by
      show ((x >>> 16) &&& 0xff) = (x / 65536) % 256
      have : (0xff : Nat) = 2 ^ 8 - 1 := by decide
      rw [this, Nat.and_two_pow_sub_one_eq_mod, Nat.shiftRight_eq_div_pow]
    have h3 : x3 = (x / 16777216) % 256 := by
      show ((x >>> 24) &&& 0xff) = (x / 16777216) % 256
      have : (0xff : Nat) = 2 ^ 8 - 1 := by decide
      rw [this, Nat.and_two_pow_sub_one_eq_mod, Nat.shiftRight_eq_div_pow]
    rw [h0, h1, h2, h3]
    omega
  let a0 := (x0 &&& 0x55) + ((x0 >>> 1) &&& 0x55)
  let a1 := (x1 &&& 0x55) + ((x1 >>> 1) &&& 0x55)
  let a2 := (x2 &&& 0x55) + ((x2 >>> 1) &&& 0x55)
  let a3 := (x3 &&& 0x55) + ((x3 >>> 1) &&& 0x55)
  have ha_lt : ∀ u : Nat, (u &&& 0x55) + ((u >>> 1) &&& 0x55) < 256 := fun u => by
    have h1 : (u &&& 0x55) ≤ 0x55 := Nat.and_le_right
    have h2 : ((u >>> 1) &&& 0x55) ≤ 0x55 := Nat.and_le_right
    omega
  have ha_eq : (x &&& 0x55555555) + ((x >>> 1) &&& 0x55555555) =
      a0 + 256 * a1 + 65536 * a2 + 16777216 * a3 := by
    have hm55 : (0x55555555 : Nat) = 0x55 + 256 * 0x55 + 65536 * 0x55 + 16777216 * 0x55 := by decide
    rw [hx_eq, hm55,
        and_pack4_rep x0 x1 x2 x3 0x55 hx0 hx1 hx2 hx3 (by decide),
        shift_and_pack4_rep x0 x1 x2 x3 1 0x55 hx0 hx1 hx2 hx3 (by decide) (by decide)]
    dsimp only [a0, a1, a2, a3]
    omega
  let b0 := (a0 &&& 0x33) + ((a0 >>> 2) &&& 0x33)
  let b1 := (a1 &&& 0x33) + ((a1 >>> 2) &&& 0x33)
  let b2 := (a2 &&& 0x33) + ((a2 >>> 2) &&& 0x33)
  let b3 := (a3 &&& 0x33) + ((a3 >>> 2) &&& 0x33)
  have hb_lt : ∀ u : Nat, (u &&& 0x33) + ((u >>> 2) &&& 0x33) < 256 := fun u => by
    have h1 : (u &&& 0x33) ≤ 0x33 := Nat.and_le_right
    have h2 : ((u >>> 2) &&& 0x33) ≤ 0x33 := Nat.and_le_right
    omega
  have hb_eq :
      (((x &&& 0x55555555) + ((x >>> 1) &&& 0x55555555)) &&& 0x33333333) +
      ((((x &&& 0x55555555) + ((x >>> 1) &&& 0x55555555)) >>> 2) &&& 0x33333333) =
      b0 + 256 * b1 + 65536 * b2 + 16777216 * b3 := by
    have hm33 : (0x33333333 : Nat) = 0x33 + 256 * 0x33 + 65536 * 0x33 + 16777216 * 0x33 := by decide
    rw [ha_eq, hm33,
        and_pack4_rep a0 a1 a2 a3 0x33 (ha_lt x0) (ha_lt x1) (ha_lt x2) (ha_lt x3) (by decide),
        shift_and_pack4_rep a0 a1 a2 a3 2 0x33 (ha_lt x0) (ha_lt x1) (ha_lt x2) (ha_lt x3) (by decide) (by decide)]
    dsimp only [b0, b1, b2, b3]
    omega
  dsimp only
  have hm0f : (0x0f0f0f0f : Nat) = 0x0f + 256 * 0x0f + 65536 * 0x0f + 16777216 * 0x0f := by decide
  rw [hb_eq, hm0f,
      and_pack4_rep b0 b1 b2 b3 0x0f (hb_lt a0) (hb_lt a1) (hb_lt a2) (hb_lt a3) (by decide),
      shift_and_pack4_rep b0 b1 b2 b3 4 0x0f (hb_lt a0) (hb_lt a1) (hb_lt a2) (hb_lt a3) (by decide) (by decide)]
  change _ = popcount8 x0 + 256 * popcount8 x1 + 65536 * popcount8 x2 + 16777216 * popcount8 x3
  dsimp only [popcount8, b0, b1, b2, b3, a0, a1, a2, a3]
  omega

private theorem popcount32_fold (p0 p1 p2 p3 : Nat)
    (hp0 : p0 ≤ 8) (hp1 : p1 ≤ 8) (hp2 : p2 ≤ 8) (hp3 : p3 ≤ 8) :
    let c := p0 + 256 * p1 + 65536 * p2 + 16777216 * p3
    let d := (c &&& 0x00ff00ff) + ((c >>> 8) &&& 0x00ff00ff)
    (d &&& 0x0000ffff) + ((d >>> 16) &&& 0x0000ffff) = p0 + p1 + p2 + p3 := by
  dsimp only
  have hcand : (p0 + 256 * p1 + 65536 * p2 + 16777216 * p3 &&& 0x00ff00ff) = p0 + 65536 * p2 :=
    and_00ff00ff p0 p1 p2 p3 (by omega) (by omega) (by omega) (by omega)
  have hcs : ((p0 + 256 * p1 + 65536 * p2 + 16777216 * p3) >>> 8) =
      p1 + 256 * p2 + 65536 * p3 + 16777216 * 0 := by
    rw [Nat.shiftRight_eq_div_pow]
    have : (2 : Nat) ^ 8 = 256 := by decide
    rw [this]; omega
  have hcsand : ((p1 + 256 * p2 + 65536 * p3 + 16777216 * 0) &&& 0x00ff00ff) = p1 + 65536 * p3 :=
    and_00ff00ff p1 p2 p3 0 (by omega) (by omega) (by omega) (by decide)
  rw [hcand, hcs, hcsand]
  have hd_eq : p0 + 65536 * p2 + (p1 + 65536 * p3) = (p0 + p1) + 65536 * (p2 + p3) := by omega
  rw [hd_eq]
  have hffff : (0x0000ffff : Nat) = 2 ^ 16 - 1 := by decide
  rw [hffff, Nat.and_two_pow_sub_one_eq_mod, Nat.and_two_pow_sub_one_eq_mod, Nat.shiftRight_eq_div_pow]
  have h216 : (2 : Nat) ^ 16 = 65536 := by decide
  rw [h216]
  omega

/-- **Exactness of `popcount32`**: for every `x < 2^32`, `popcount32 x = bitWeight x 32`. -/
theorem popcount32_eq_bitWeight32 (x : Nat) (hx : x < 2 ^ 32) :
    popcount32 x = bitWeight x 32 := by
  unfold popcount32
  have hc := swar_step_c_bytes x hx
  dsimp only at hc ⊢
  rw [hc, popcount32_fold _ _ _ _
      (popcount8_le_8 _ (byte_lt_256 x))
      (popcount8_le_8 _ (byte_lt_256 (x >>> 8)))
      (popcount8_le_8 _ (byte_lt_256 (x >>> 16)))
      (popcount8_le_8 _ (byte_lt_256 (x >>> 24))),
      bitWeight_32_bytes,
      popcount8_eq_bitWeight _ (byte_lt_256 x),
      popcount8_eq_bitWeight _ (byte_lt_256 (x >>> 8)),
      popcount8_eq_bitWeight _ (byte_lt_256 (x >>> 16)),
      popcount8_eq_bitWeight _ (byte_lt_256 (x >>> 24))]

theorem popcount32_eq_hammingWeight (n x : Nat) (hn : n ≤ 32) (hx : x < 2 ^ n) :
    popcount32 x = hammingWeight n (wordVec n x) := by
  have hx32 : x < 2 ^ 32 := Nat.lt_of_lt_of_le hx (Nat.pow_le_pow_right (by omega) hn)
  rw [popcount32_eq_bitWeight32 x hx32, bitWeight_eq_of_lt_two_pow x n 32 hn hx, hammingWeight_wordVec]

theorem popcount32_xor_eq_hammingDist (n x y : Nat) (hn : n ≤ 32)
    (hx : x < 2 ^ n) (hy : y < 2 ^ n) :
    popcount32 (x ^^^ y) = hammingDist n (wordVec n x) (wordVec n y) := by
  have hxy : (x ^^^ y) < 2 ^ n := Nat.xor_lt_two_pow hx hy
  rw [popcount32_eq_hammingWeight n (x ^^^ y) hn hxy]
  unfold hammingDist hammingWeight
  apply hammingWeightAux_congr
  intro i
  simp [wordVec, Nat.testBit_xor]

theorem wordVec_ne_of_ne (n x y : Nat) (hx : x < 2 ^ n) (hy : y < 2 ^ n) (hne : x ≠ y) :
    wordVec n x ≠ wordVec n y := by
  intro heq
  apply hne
  apply Nat.eq_of_testBit_eq
  intro i
  by_cases hi : i < n
  · exact congrFun heq ⟨i, hi⟩
  · have h1 : x.testBit i = false :=
      Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le hx (Nat.pow_le_pow_right (by omega) (by omega)))
    have h2 : y.testBit i = false :=
      Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le hy (Nat.pow_le_pow_right (by omega) (by omega)))
    rw [h1, h2]

theorem checkBounds_sound (bound : Nat) (words : List Nat) (h : checkBounds bound words = true) :
    ∀ i : Fin words.length, words.get i < bound := by
  induction words with
  | nil => intro i; exact Fin.elim0 i
  | cons x xs ih =>
    simp only [checkBounds, Bool.and_eq_true, Nat.blt_eq] at h
    intro i
    rcases i with ⟨idx, hlt⟩
    cases idx with
    | zero => exact h.1
    | succ idx => exact ih h.2 ⟨idx, Nat.lt_of_succ_lt_succ hlt⟩

theorem checkWeights_sound (w : Nat) (words : List Nat) (h : checkWeights w words = true) :
    ∀ i : Fin words.length, popcount32 (words.get i) = w := by
  induction words with
  | nil => intro i; exact Fin.elim0 i
  | cons x xs ih =>
    simp only [checkWeights, Bool.and_eq_true, beq_iff_eq] at h
    intro i
    rcases i with ⟨idx, hlt⟩
    cases idx with
    | zero => exact h.1
    | succ idx => exact ih h.2 ⟨idx, Nat.lt_of_succ_lt_succ hlt⟩

theorem checkDistAgainst_sound (d x : Nat) (ys : List Nat) (h : checkDistAgainst d x ys = true) :
    ∀ j : Fin ys.length, x ≠ ys.get j ∧ d ≤ popcount32 (x ^^^ ys.get j) := by
  induction ys with
  | nil => intro j; exact Fin.elim0 j
  | cons y ys ih =>
    simp only [checkDistAgainst, Bool.and_eq_true, bne_iff_ne, Nat.ble_eq] at h
    intro j
    rcases j with ⟨idx, hlt⟩
    cases idx with
    | zero => exact h.1
    | succ idx => exact ih h.2 ⟨idx, Nat.lt_of_succ_lt_succ hlt⟩

theorem checkAllDist_sound (d : Nat) (words : List Nat) (h : checkAllDist d words = true) :
    ∀ i j : Fin words.length, i.val < j.val →
      words.get i ≠ words.get j ∧ d ≤ popcount32 (words.get i ^^^ words.get j) := by
  induction words with
  | nil => intro i; exact Fin.elim0 i
  | cons x xs ih =>
    simp only [checkAllDist, Bool.and_eq_true] at h
    intro i j hij
    rcases i with ⟨iv, hilt⟩
    rcases j with ⟨jv, hjlt⟩
    dsimp only at hij
    cases iv with
    | zero =>
      cases jv with
      | zero => omega
      | succ jv =>
        exact checkDistAgainst_sound d x xs h.1 ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩
    | succ iv =>
      cases jv with
      | zero => omega
      | succ jv =>
        exact ih h.2 ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩ ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩ (by dsimp only; omega)

/-- **End-to-end soundness for binary codes `A(n, d)`**: if `n ≤ 32`, `words.length = M`,
every word lies in `[0, 2^n)`, and `checkAllDist d words = true`, then `ValidBinaryCode n d M`. -/
theorem validBinaryCode_of_check (n d M : Nat) (hn : n ≤ 32) (words : List Nat)
    (hlen : words.length = M)
    (hb : checkBounds (1 <<< n) words = true)
    (hd : checkAllDist d words = true) :
    ValidBinaryCode n d M := by
  have hpow : (1 <<< n) = 2 ^ n := by rw [Nat.shiftLeft_eq, Nat.one_mul]
  rw [hpow] at hb
  have hbd := checkBounds_sound (2 ^ n) words hb
  have hdist := checkAllDist_sound d words hd
  refine ⟨words.map (wordVec n), by simp [hlen], ?_⟩
  intro i j hij
  have hi_len : i.val < words.length := by simpa using i.isLt
  have hj_len : j.val < words.length := by simpa using j.isLt
  let i' : Fin words.length := ⟨i.val, hi_len⟩
  let j' : Fin words.length := ⟨j.val, hj_len⟩
  have hgi : (words.map (wordVec n)).get i = wordVec n (words.get i') := by simp [i']
  have hgj : (words.map (wordVec n)).get j = wordVec n (words.get j') := by simp [j']
  rw [hgi, hgj]
  have hne_val : i.val ≠ j.val := fun heq => hij (Fin.ext heq)
  by_cases hlt : i.val < j.val
  · rcases hdist i' j' hlt with ⟨hne, hdp⟩
    refine ⟨wordVec_ne_of_ne n _ _ (hbd i') (hbd j') hne, ?_⟩
    rw [← popcount32_xor_eq_hammingDist n _ _ hn (hbd i') (hbd j')]
    exact hdp
  · have hgt : j.val < i.val := by omega
    rcases hdist j' i' hgt with ⟨hne, hdp⟩
    refine ⟨Ne.symm (wordVec_ne_of_ne n _ _ (hbd j') (hbd i') hne), ?_⟩
    rw [hammingDist_symm, ← popcount32_xor_eq_hammingDist n _ _ hn (hbd j') (hbd i')]
    exact hdp

/-- **End-to-end soundness for binary constant-weight codes `A(n, d, w)`**: if `n ≤ 32`,
`words.length = M`, every word lies in `[0, 2^n)` with weight `w`, and
`checkAllDist d words = true`, then `ValidConstantWeightCode n d w M`. -/
theorem validConstantWeightCode_of_check (n d w M : Nat) (hn : n ≤ 32) (words : List Nat)
    (hlen : words.length = M)
    (hb : checkBounds (1 <<< n) words = true)
    (hw : checkWeights w words = true)
    (hd : checkAllDist d words = true) :
    ValidConstantWeightCode n d w M := by
  have hpow : (1 <<< n) = 2 ^ n := by rw [Nat.shiftLeft_eq, Nat.one_mul]
  rw [hpow] at hb
  have hbd := checkBounds_sound (2 ^ n) words hb
  have hwt := checkWeights_sound w words hw
  have hdist := checkAllDist_sound d words hd
  refine ⟨words.map (wordVec n), by simp [hlen], ?_, ?_⟩
  · intro i
    have hi_len : i.val < words.length := by simpa using i.isLt
    let i' : Fin words.length := ⟨i.val, hi_len⟩
    have hgi : (words.map (wordVec n)).get i = wordVec n (words.get i') := by simp [i']
    rw [hgi, ← popcount32_eq_hammingWeight n _ hn (hbd i')]
    exact hwt i'
  · intro i j hij
    have hi_len : i.val < words.length := by simpa using i.isLt
    have hj_len : j.val < words.length := by simpa using j.isLt
    let i' : Fin words.length := ⟨i.val, hi_len⟩
    let j' : Fin words.length := ⟨j.val, hj_len⟩
    have hgi : (words.map (wordVec n)).get i = wordVec n (words.get i') := by simp [i']
    have hgj : (words.map (wordVec n)).get j = wordVec n (words.get j') := by simp [j']
    rw [hgi, hgj]
    have hne_val : i.val ≠ j.val := fun heq => hij (Fin.ext heq)
    by_cases hlt : i.val < j.val
    · rcases hdist i' j' hlt with ⟨hne, hdp⟩
      refine ⟨wordVec_ne_of_ne n _ _ (hbd i') (hbd j') hne, ?_⟩
      rw [← popcount32_xor_eq_hammingDist n _ _ hn (hbd i') (hbd j')]
      exact hdp
    · have hgt : j.val < i.val := by omega
      rcases hdist j' i' hgt with ⟨hne, hdp⟩
      refine ⟨Ne.symm (wordVec_ne_of_ne n _ _ (hbd j') (hbd i') hne), ?_⟩
      rw [hammingDist_symm, ← popcount32_xor_eq_hammingDist n _ _ hn (hbd j') (hbd i')]
      exact hdp

end CodingBounds
