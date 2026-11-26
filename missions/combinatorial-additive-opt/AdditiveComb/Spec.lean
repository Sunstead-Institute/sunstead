/-!
# Additive Combinatorics: Cap Sets in F_3^n, 3-AP-Free (Salem–Spencer) Sets, and Sidon Sets

This module formalizes three classic additive combinatorics maximization frontiers in pure
Lean 4.36.0 (zero Mathlib, standard axioms only):

1. **Cap Sets in `F_3^n` (`ValidCapSet n M`)**: subsets of `Fin n → Fin 3` containing no
   three distinct points summing to `0 (mod 3)` (no affine line). Verified in `O(M^2)` using
   a carry-free 2-bit-per-trit SWAR line-completion operator (`thirdPointBits`) and a bitmask
   membership table (`checkCapSet`), proved completely sound in `validCapSet_of_check`.
2. **3-AP-Free / Salem–Spencer Sets (`ValidAP3Free N M`)**: subsets of `{0, ..., N - 1}`
   containing no three-term arithmetic progression `a + c = 2 * b` (`a < b < c`), certifying
   `r_3(N) ≥ M`. Proved sound in `validAP3Free_of_check`.
3. **Sidon Sets / B_2-Sets (`ValidSidonSet N M`)**: subsets of `{0, ..., N - 1}` whose
   pairwise sums `a + b` (`a ≤ b`) are all distinct, verified via a pairwise positive-difference
   bitmask (`checkSidonDiffs`) with full equivalence proof (`validSidonSet_of_check`).

Upstream benchmark records for Cap Sets are pinned to Google DeepMind's
`google-deepmind/funsearch` at commit `cc53f274237d7ab05c19df939edbc1f9616a7c19` (Apache-2.0).
-/

namespace AdditiveComb

/-! ## Mission target predicates -/

/-- Existence of a cap set of size `M` in `F_3^n`: `M` pairwise distinct vectors in
`Fin n → Fin 3` with no three distinct vectors summing to `0 (mod 3)` coordinatewise. -/
def ValidCapSet (n M : Nat) : Prop :=
  ∃ S : List (Fin n → Fin 3),
    S.length = M ∧
    (∀ i j : Fin S.length, i ≠ j → S.get i ≠ S.get j) ∧
    (∀ i j k : Fin S.length, i ≠ j → i ≠ k → j ≠ k →
      ¬ ∀ c : Fin n, ((S.get i c).val + (S.get j c).val + (S.get k c).val) % 3 = 0)

/-- Existence of a 3-AP-free (Salem–Spencer) subset of `{0, ..., N - 1}` of size `M`,
certifying `r_3(N) ≥ M`. -/
def ValidAP3Free (N M : Nat) : Prop :=
  ∃ S : List Nat,
    S.length = M ∧
    (∀ x ∈ S, x < N) ∧
    (∀ i j : Fin S.length, i ≠ j → S.get i ≠ S.get j) ∧
    (∀ a ∈ S, ∀ b ∈ S, ∀ c ∈ S, a < b → b < c → a + c ≠ 2 * b)

/-- Existence of a Sidon (`B_2`) subset of `{0, ..., N - 1}` of size `M`:
all pairwise sums `a + b` (`a ≤ b`) are distinct. -/
def ValidSidonSet (N M : Nat) : Prop :=
  ∃ S : List Nat,
    S.length = M ∧
    (∀ x ∈ S, x < N) ∧
    (∀ i j : Fin S.length, i ≠ j → S.get i ≠ S.get j) ∧
    (∀ a ∈ S, ∀ b ∈ S, ∀ c ∈ S, ∀ d ∈ S,
      a ≤ b → c ≤ d → a + b = c + d → a = c ∧ b = d)

/-! ## 1. Cap Sets in F_3^n: 2-bit-per-trit SWAR verifier and soundness -/

/-- Low-bit mask `0x555...5` with bit `2*c` set for `c < n`. -/
def mask01 : Nat → Nat
  | 0 => 0
  | n + 1 => 1 ||| (mask01 n <<< 2)

/-- Full `2*n`-bit mask `(1 <<< (2 * n)) - 1`. -/
def fullMask (n : Nat) : Nat := (1 <<< (2 * n)) - 1

/-- Check that `x < 2^(2*n)` and every 2-bit lane of `x` is `< 3` (never `11`). -/
def validPackedPoint (n : Nat) (x : Nat) : Bool :=
  Nat.blt x (1 <<< (2 * n)) && (((x &&& (x >>> 1)) &&& mask01 n) == 0)

/-- SWAR bitwise third point completing the affine line through `x` and `y` in `F_3^n`:
in every 2-bit lane, if `x_c = y_c` returns `x_c`, else returns the third value in `{0, 1, 2}`. -/
def thirdPointBits (m01 fmask x y : Nat) : Nat :=
  let diff := x ^^^ y
  let neq := (diff ||| (diff >>> 1)) &&& m01
  let neq2 := neq ||| (neq <<< 1)
  (diff ^^^ neq2) ||| (x &&& (fmask ^^^ neq2))

/-- Build presence bitmask while checking valid 2-bit trit bounds and pairwise distinctness. -/
def buildCapMask (n : Nat) : List Nat → Nat → Option Nat
  | [], acc => some acc
  | x :: xs, acc =>
    if validPackedPoint n x && !(acc.testBit x) then
      buildCapMask n xs (acc ||| (1 <<< x))
    else none

/-- Check that for `x` and every `y ∈ ys`, `thirdPointBits m01 fmask x y` is not in `present`. -/
def checkCapAgainst (m01 fmask present x : Nat) : List Nat → Bool
  | [] => true
  | y :: ys =>
    let z := thirdPointBits m01 fmask x y
    (((present >>> z) &&& 1) == 0) && checkCapAgainst m01 fmask present x ys

/-- Check all pairs `i < j` in `pts` against `present`. -/
def checkCapPairs (m01 fmask present : Nat) : List Nat → Bool
  | [] => true
  | x :: xs => checkCapAgainst m01 fmask present x xs && checkCapPairs m01 fmask present xs

/-- Complete kernel-decidable cap-set verifier for `F_3^n`. -/
def checkCapSet (n : Nat) (pts : List Nat) : Bool :=
  match buildCapMask n pts 0 with
  | none => false
  | some present => checkCapPairs (mask01 n) (fullMask n) present pts

/-- Decode lane `c` of a 2-bit-packed `Nat` into `Nat` (`(x >>> (2*c)) &&& 3`). -/
def laneVal (x c : Nat) : Nat :=
  (if x.testBit (2 * c) then 1 else 0) + (if x.testBit (2 * c + 1) then 2 else 0)

theorem mask01_testBit (n i : Nat) :
    (mask01 n).testBit i = (decide (i < 2 * n) && decide (i % 2 = 0)) := by
  induction n generalizing i with
  | zero => simp [mask01]
  | succ n ih =>
    simp only [mask01, Nat.testBit_or, Nat.testBit_shiftLeft]
    cases i with
    | zero => simp
    | succ i =>
      cases i with
      | zero => simp [show (1 : Nat).testBit 1 = false by decide]
      | succ i =>
        have h1 : (1 : Nat).testBit (i + 2) = false := by
          apply Nat.testBit_lt_two_pow
          have : 4 ≤ 2 ^ (i + 2) := by
            have : (4 : Nat) = 2 ^ 2 := by decide
            rw [this]; exact Nat.pow_le_pow_right (by omega) (by omega)
          omega
        have hge : decide (i + 2 ≥ 2) = true := decide_eq_true (by omega)
        have hsub : i + 2 - 2 = i := by omega
        rw [h1, hge, hsub, ih i]
        have hlt : decide (i < 2 * n) = decide (i + 2 < 2 * (n + 1)) := by
          by_cases h : i < 2 * n
          · rw [decide_eq_true h, decide_eq_true (by omega)]
          · rw [decide_eq_false h, decide_eq_false (by omega)]
        have hmod : decide (i % 2 = 0) = decide ((i + 2) % 2 = 0) := by
          have : (i + 2) % 2 = i % 2 := by omega
          rw [this]
        simp [hlt, hmod]

theorem validPackedPoint_lane_lt (n x : Nat) (h : validPackedPoint n x = true) :
    x < 2 ^ (2 * n) ∧ ∀ c : Nat, c < n → laneVal x c < 3 := by
  simp only [validPackedPoint, Bool.and_eq_true, Nat.blt_eq, beq_iff_eq] at h
  have hpow : (1 <<< (2 * n)) = 2 ^ (2 * n) := by rw [Nat.shiftLeft_eq, Nat.one_mul]
  rw [hpow] at h
  refine ⟨h.1, ?_⟩
  intro c hc
  have htb := congrArg (fun z => z.testBit (2 * c)) h.2
  rw [Nat.testBit_and, Nat.testBit_and, Nat.testBit_shiftRight, mask01_testBit] at htb
  have h1 : decide (2 * c < 2 * n) = true := decide_eq_true (by omega)
  have h2 : decide (2 * c % 2 = 0) = true := decide_eq_true (by omega)
  have hplus : 1 + 2 * c = 2 * c + 1 := by omega
  rw [h1, h2, hplus] at htb
  unfold laneVal
  cases hb0 : x.testBit (2 * c) <;> cases hb1 : x.testBit (2 * c + 1)
  · decide
  · decide
  · decide
  · rw [hb0, hb1] at htb; simp at htb

theorem validPackedPoint_hi_zero (n x : Nat) (h : x < 2 ^ (2 * n)) :
    ∀ i, 2 * n ≤ i → x.testBit i = false := fun i hi =>
  Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le h (Nat.pow_le_pow_right (by omega) hi))

theorem thirdPointBits_hi_zero (n x y : Nat)
    (hx : x < 2 ^ (2 * n)) (hy : y < 2 ^ (2 * n)) (i : Nat) (hi : 2 * n ≤ i) :
    (thirdPointBits (mask01 n) (fullMask n) x y).testBit i = false := by
  unfold thirdPointBits fullMask
  have hpow : (1 <<< (2 * n)) = 2 ^ (2 * n) := by rw [Nat.shiftLeft_eq, Nat.one_mul]
  rw [hpow]
  have hxi : x.testBit i = false := validPackedPoint_hi_zero n x hx i hi
  have hyi : y.testBit i = false := validPackedPoint_hi_zero n y hy i hi
  have hfm : (2 ^ (2 * n) - 1).testBit i = false := by
    rw [Nat.testBit_two_pow_sub_one]; exact decide_eq_false (by omega)
  have hm0 : (mask01 n).testBit i = false := by
    rw [mask01_testBit]; simp [decide_eq_false (by omega : ¬ (i < 2 * n))]
  have hneq_i : (((x ^^^ y) ||| ((x ^^^ y) >>> 1)) &&& mask01 n).testBit i = false := by
    rw [Nat.testBit_and, hm0]; simp
  have hneq_sh : ((((x ^^^ y) ||| ((x ^^^ y) >>> 1)) &&& mask01 n) <<< 1).testBit i = false := by
    rw [Nat.testBit_shiftLeft]
    by_cases hi1 : 1 ≤ i
    · have hm1 : (mask01 n).testBit (i - 1) = false := by
        rw [mask01_testBit]
        by_cases hlt : i - 1 < 2 * n
        · have heq : i - 1 = 2 * n - 1 := by omega
          have hodd : (i - 1) % 2 ≠ 0 := by omega
          simp [decide_eq_false hodd]
        · simp [decide_eq_false hlt]
      rw [Nat.testBit_and, hm1]; simp
    · simp [decide_eq_false hi1]
  simp only [Nat.testBit_or, Nat.testBit_xor, Nat.testBit_and, hxi, hyi, hfm, hneq_i, hneq_sh]
  rfl

theorem thirdPointBits_lane (n x y : Nat)
    (hx : validPackedPoint n x = true) (hy : validPackedPoint n y = true)
    (c : Nat) (hc : c < n) :
    let z := thirdPointBits (mask01 n) (fullMask n) x y
    laneVal z c < 3 ∧ (laneVal x c + laneVal y c + laneVal z c) % 3 = 0 := by
  have hx_ok := (validPackedPoint_lane_lt n x hx).2 c hc
  have hy_ok := (validPackedPoint_lane_lt n y hy).2 c hc
  unfold laneVal at hx_ok hy_ok
  unfold thirdPointBits fullMask laneVal
  have hpow : (1 <<< (2 * n)) = 2 ^ (2 * n) := by rw [Nat.shiftLeft_eq, Nat.one_mul]
  rw [hpow]
  have hm0 : (mask01 n).testBit (2 * c) = true := by
    rw [mask01_testBit]; simp [hc]
  have hm1 : (mask01 n).testBit (2 * c + 1) = false := by
    rw [mask01_testBit]; simp
  have hm_prev : ∀ (h : 1 ≤ 2 * c), (mask01 n).testBit (2 * c - 1) = false := fun h => by
    rw [mask01_testBit]; simp [decide_eq_false (by omega : ¬ ((2 * c - 1) % 2 = 0))]
  have hf0 : (2 ^ (2 * n) - 1).testBit (2 * c) = true := by
    rw [Nat.testBit_two_pow_sub_one]; exact decide_eq_true (by omega)
  have hf1 : (2 ^ (2 * n) - 1).testBit (2 * c + 1) = true := by
    rw [Nat.testBit_two_pow_sub_one]; exact decide_eq_true (by omega)
  have hsh0 : ((((x ^^^ y) ||| ((x ^^^ y) >>> 1)) &&& mask01 n) <<< 1).testBit (2 * c) = false := by
    rw [Nat.testBit_shiftLeft]
    by_cases h : 1 ≤ 2 * c
    · rw [Nat.testBit_and, hm_prev h]; simp
    · simp [decide_eq_false h]
  have hsh1 : ((((x ^^^ y) ||| ((x ^^^ y) >>> 1)) &&& mask01 n) <<< 1).testBit (2 * c + 1) =
      ((x.testBit (2 * c) ^^ y.testBit (2 * c)) || (x.testBit (2 * c + 1) ^^ y.testBit (2 * c + 1))) := by
    rw [Nat.testBit_shiftLeft]
    have hge : decide (2 * c + 1 ≥ 1) = true := decide_eq_true (by omega)
    have hsub : 2 * c + 1 - 1 = 2 * c := by omega
    have hplus : 1 + 2 * c = 2 * c + 1 := by omega
    rw [hge, hsub, Nat.testBit_and, hm0, Nat.testBit_or, Nat.testBit_shiftRight, hplus,
        Nat.testBit_xor, Nat.testBit_xor]
    simp
  have hneq0 : (((x ^^^ y) ||| ((x ^^^ y) >>> 1)) &&& mask01 n).testBit (2 * c) =
      ((x.testBit (2 * c) ^^ y.testBit (2 * c)) || (x.testBit (2 * c + 1) ^^ y.testBit (2 * c + 1))) := by
    have hplus : 1 + 2 * c = 2 * c + 1 := by omega
    rw [Nat.testBit_and, hm0, Nat.testBit_or, Nat.testBit_shiftRight, hplus,
        Nat.testBit_xor, Nat.testBit_xor]
    simp
  have hneq1 : (((x ^^^ y) ||| ((x ^^^ y) >>> 1)) &&& mask01 n).testBit (2 * c + 1) = false := by
    rw [Nat.testBit_and, hm1]; simp
  dsimp only
  simp only [Nat.testBit_or, Nat.testBit_xor, Nat.testBit_and, hf0, hf1, hneq0, hneq1, hsh0, hsh1]
  cases x0 : x.testBit (2 * c) <;> cases x1 : x.testBit (2 * c + 1) <;>
    cases y0 : y.testBit (2 * c) <;> cases y1 : y.testBit (2 * c + 1) <;>
    simp_all

theorem eq_of_laneVal_eq (n x y : Nat)
    (hx : x < 2 ^ (2 * n)) (hy : y < 2 ^ (2 * n))
    (hl : ∀ c : Nat, c < n → laneVal x c = laneVal y c) :
    x = y := by
  apply Nat.eq_of_testBit_eq
  intro i
  by_cases hi : i < 2 * n
  · let c := i / 2
    have hc : c < n := by omega
    have hlc := hl c hc
    unfold laneVal at hlc
    by_cases hev : i % 2 = 0
    · have hi_eq : i = 2 * c := by omega
      rw [hi_eq]
      cases h1 : x.testBit (2 * c) <;> cases h2 : x.testBit (2 * c + 1) <;>
        cases h3 : y.testBit (2 * c) <;> cases h4 : y.testBit (2 * c + 1) <;>
        simp_all
    · have hi_eq : i = 2 * c + 1 := by omega
      rw [hi_eq]
      cases h1 : x.testBit (2 * c) <;> cases h2 : x.testBit (2 * c + 1) <;>
        cases h3 : y.testBit (2 * c) <;> cases h4 : y.testBit (2 * c + 1) <;>
        simp_all
  · rw [validPackedPoint_hi_zero n x hx i (by omega),
        validPackedPoint_hi_zero n y hy i (by omega)]

theorem buildCapMask_sound (n : Nat) (pts : List Nat) (acc final : Nat)
    (h : buildCapMask n pts acc = some final) :
    (∀ x ∈ pts, validPackedPoint n x = true) ∧
    (∀ i j : Fin pts.length, i ≠ j → pts.get i ≠ pts.get j) ∧
    (∀ z, final.testBit z = true ↔ acc.testBit z = true ∨ z ∈ pts) := by
  induction pts generalizing acc with
  | nil =>
    simp only [buildCapMask, Option.some.injEq] at h
    subst h
    refine ⟨(fun _ hm => nomatch hm), (fun i => Fin.elim0 i), fun z => by simp⟩
  | cons x xs ih =>
    simp only [buildCapMask] at h
    split at h
    · next hcond =>
      simp only [Bool.and_eq_true, Bool.not_eq_true'] at hcond
      rcases hcond with ⟨hvalid, hnotacc⟩
      let acc' := acc ||| (1 <<< x)
      have hacc'_tb : ∀ z, acc'.testBit z = (acc.testBit z || decide (x = z)) := by
        intro z
        have hbit : (1 <<< x) = 2 ^ x := by rw [Nat.shiftLeft_eq, Nat.one_mul]
        simp only [acc', Nat.testBit_or, hbit, Nat.testBit_two_pow]
      rcases ih acc' h with ⟨hval_xs, hnodup_xs, hmask_xs⟩
      have hx_not_in_xs : x ∉ xs := by
        -- Actually if x ∈ xs, buildCapMask would fail when seeing x since acc'.testBit x = true!
        -- Prove directly by a helper lemma: acc.testBit y = true → y ∉ ys when buildCapMask succeeds!
        have hdisj : ∀ (ys : List Nat) (a res : Nat), buildCapMask n ys a = some res →
            ∀ y ∈ ys, a.testBit y = false := by
          intro ys
          induction ys with
          | nil => intro _ _ _ y hy; cases hy
          | cons u us ihu =>
            intro a res hres y hy
            simp only [buildCapMask] at hres
            split at hres
            · next hc =>
              simp only [Bool.and_eq_true, Bool.not_eq_true'] at hc
              rcases List.mem_cons.1 hy with rfl | hy'
              · exact hc.2
              · have h1 := ihu (a ||| (1 <<< u)) res hres y hy'
                rw [Nat.testBit_or] at h1
                exact (Bool.or_eq_false_iff.1 h1).1
            · cases hres
        intro hmem
        have hf := hdisj xs acc' final h x hmem
        rw [hacc'_tb] at hf; simp at hf
      refine ⟨?_, ?_, ?_⟩
      · intro y hy
        rcases List.mem_cons.1 hy with rfl | hy'
        · exact hvalid
        · exact hval_xs y hy'
      · intro i j hij
        rcases i with ⟨iv, hilt⟩
        rcases j with ⟨jv, hjlt⟩
        cases iv with
        | zero =>
          cases jv with
          | zero => exact False.elim (hij rfl)
          | succ jv =>
            intro heq
            have hmem : x ∈ xs := by
              have : xs.get ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩ = x := heq.symm
              rw [← this]; exact List.get_mem _ _
            exact hx_not_in_xs hmem
        | succ iv =>
          cases jv with
          | zero =>
            intro heq
            have hmem : x ∈ xs := by
              have : xs.get ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩ = x := heq
              rw [← this]; exact List.get_mem _ _
            exact hx_not_in_xs hmem
          | succ jv =>
            exact hnodup_xs ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩ ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩
              (fun heq => hij (Fin.ext (by have := congrArg Fin.val heq; dsimp only at this ⊢; omega)))
      · intro z
        rw [hmask_xs z, hacc'_tb z]
        constructor
        · intro hz
          rcases hz with h1 | h2
          · rcases Bool.or_eq_true_iff.1 h1 with ha | hxz
            · exact Or.inl ha
            · exact Or.inr (List.mem_cons.2 (Or.inl (of_decide_eq_true hxz).symm))
          · exact Or.inr (List.mem_cons_of_mem _ h2)
        · intro hz
          rcases hz with ha | hm
          · exact Or.inl (by simp [ha])
          · rcases List.mem_cons.1 hm with rfl | hm'
            · exact Or.inl (by simp)
            · exact Or.inr hm'
    · cases h

theorem checkCapAgainst_sound (m01 fmask present x : Nat) (ys : List Nat)
    (h : checkCapAgainst m01 fmask present x ys = true) :
    ∀ j : Fin ys.length, present.testBit (thirdPointBits m01 fmask x (ys.get j)) = false := by
  induction ys with
  | nil => intro j; exact Fin.elim0 j
  | cons y ys ih =>
    simp only [checkCapAgainst, Bool.and_eq_true, beq_iff_eq] at h
    intro j
    rcases j with ⟨jv, hjlt⟩
    cases jv with
    | zero =>
      change present.testBit (thirdPointBits m01 fmask x y) = false
      have h0 := h.1
      rw [Nat.testBit_eq_decide_div_mod_eq, ← Nat.shiftRight_eq_div_pow]
      have hmod : (present >>> thirdPointBits m01 fmask x y) % 2 =
          ((present >>> thirdPointBits m01 fmask x y) &&& 1) := by
        have h1 : (1 : Nat) = 2 ^ 1 - 1 := by decide
        rw [h1, Nat.and_two_pow_sub_one_eq_mod]
      rw [hmod, h0]; rfl
    | succ jv =>
      exact ih h.2 ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩

theorem checkCapPairs_sound (m01 fmask present : Nat) (pts : List Nat)
    (h : checkCapPairs m01 fmask present pts = true) :
    ∀ i j : Fin pts.length, i.val < j.val →
      present.testBit (thirdPointBits m01 fmask (pts.get i) (pts.get j)) = false := by
  induction pts with
  | nil => intro i; exact Fin.elim0 i
  | cons x xs ih =>
    simp only [checkCapPairs, Bool.and_eq_true] at h
    intro i j hij
    rcases i with ⟨iv, hilt⟩
    rcases j with ⟨jv, hjlt⟩
    dsimp only at hij
    cases iv with
    | zero =>
      cases jv with
      | zero => omega
      | succ jv => exact checkCapAgainst_sound m01 fmask present x xs h.1 ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩
    | succ iv =>
      cases jv with
      | zero => omega
      | succ jv =>
        exact ih h.2 ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩ ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩ (by dsimp only; omega)

/-- Decode a valid packed point `x` into `Fin n → Fin 3`. -/
def decodeCapPoint (n : Nat) (x : Nat) : Fin n → Fin 3 :=
  fun c =>
    let v := laneVal x c.val
    if h : v < 3 then ⟨v, h⟩ else ⟨0, by decide⟩

/-- **End-to-end soundness for Cap Sets in `F_3^n`**: if `pts.length = M` and
`checkCapSet n pts = true`, then `ValidCapSet n M`. -/
theorem validCapSet_of_check (n M : Nat) (pts : List Nat)
    (hlen : pts.length = M) (hchk : checkCapSet n pts = true) :
    ValidCapSet n M := by
  unfold checkCapSet at hchk
  cases hbm : buildCapMask n pts 0 with
  | none => rw [hbm] at hchk; cases hchk
  | some present =>
    rw [hbm] at hchk
    rcases buildCapMask_sound n pts 0 present hbm with ⟨hvalid, hnodup, hmask⟩
    have hpairs := checkCapPairs_sound (mask01 n) (fullMask n) present pts hchk
    have hdecode_val : ∀ (x : Nat), validPackedPoint n x = true → ∀ c : Fin n,
        (decodeCapPoint n x c).val = laneVal x c.val := by
      intro x hx c
      unfold decodeCapPoint
      have hlt := (validPackedPoint_lane_lt n x hx).2 c.val c.isLt
      simp [hlt]
    refine ⟨pts.map (decodeCapPoint n), by simp [hlen], ?_, ?_⟩
    · intro i j hij heq
      let i' : Fin pts.length := ⟨i.val, by simpa using i.isLt⟩
      let j' : Fin pts.length := ⟨j.val, by simpa using j.isLt⟩
      have hne : i' ≠ j' := fun h => hij (Fin.ext (by have := congrArg Fin.val h; exact this))
      have hpi : validPackedPoint n (pts.get i') = true := hvalid _ (List.get_mem _ _)
      have hpj : validPackedPoint n (pts.get j') = true := hvalid _ (List.get_mem _ _)
      apply hnodup i' j' hne
      apply eq_of_laneVal_eq n _ _ (validPackedPoint_lane_lt n _ hpi).1 (validPackedPoint_lane_lt n _ hpj).1
      intro c hc
      have hfc := congrArg Fin.val (congrFun heq ⟨c, hc⟩)
      have hgi : (pts.map (decodeCapPoint n)).get i = decodeCapPoint n (pts.get i') := by simp [i']
      have hgj : (pts.map (decodeCapPoint n)).get j = decodeCapPoint n (pts.get j') := by simp [j']
      rw [hgi, hgj, hdecode_val _ hpi ⟨c, hc⟩, hdecode_val _ hpj ⟨c, hc⟩] at hfc
      exact hfc
    · intro i j k hij hik hjk hline
      let i' : Fin pts.length := ⟨i.val, by simpa using i.isLt⟩
      let j' : Fin pts.length := ⟨j.val, by simpa using j.isLt⟩
      let k' : Fin pts.length := ⟨k.val, by simpa using k.isLt⟩
      have hpi : validPackedPoint n (pts.get i') = true := hvalid _ (List.get_mem _ _)
      have hpj : validPackedPoint n (pts.get j') = true := hvalid _ (List.get_mem _ _)
      have hpk : validPackedPoint n (pts.get k') = true := hvalid _ (List.get_mem _ _)
      have hne_ij : i'.val ≠ j'.val := fun h => hij (Fin.ext h)
      -- WLOG order the first two indices as a < b
      have hcheck_ordered : ∀ (a b : Fin pts.length), a.val < b.val →
          validPackedPoint n (pts.get a) = true → validPackedPoint n (pts.get b) = true →
          (∀ c : Fin n, (laneVal (pts.get a) c.val + laneVal (pts.get b) c.val + laneVal (pts.get k') c.val) % 3 = 0) →
          False := by
        intro a b hab hpa hpb hsum
        let z := thirdPointBits (mask01 n) (fullMask n) (pts.get a) (pts.get b)
        have hz_lt : z < 2 ^ (2 * n) := by
          have hhi := thirdPointBits_hi_zero n (pts.get a) (pts.get b)
            (validPackedPoint_lane_lt n _ hpa).1 (validPackedPoint_lane_lt n _ hpb).1
          have hlt_of_hi : ∀ (v m : Nat), (∀ r, m ≤ r → v.testBit r = false) → v < 2 ^ m := by
            intro v m hzero
            have hmod : v = v % 2 ^ m := by
              apply Nat.eq_of_testBit_eq
              intro r
              rw [Nat.testBit_mod_two_pow]
              by_cases hr : r < m
              · simp [hr]
              · simp [hr, hzero r (by omega)]
            rw [hmod]
            exact Nat.mod_lt v (Nat.two_pow_pos m)
          exact hlt_of_hi z (2 * n) hhi
        have hz_eq : z = pts.get k' := by
          apply eq_of_laneVal_eq n z (pts.get k') hz_lt (validPackedPoint_lane_lt n _ hpk).1
          intro c hc
          have htz := thirdPointBits_lane n (pts.get a) (pts.get b) hpa hpb c hc
          have hlk := (validPackedPoint_lane_lt n _ hpk).2 c hc
          have hsc := hsum ⟨c, hc⟩
          dsimp only [z] at htz hsc ⊢
          omega
        have hfalse := hpairs a b hab
        change present.testBit z = false at hfalse
        rw [hz_eq] at hfalse
        have htrue : present.testBit (pts.get k') = true :=
          (hmask (pts.get k')).2 (Or.inr (List.get_mem _ _))
        rw [htrue] at hfalse; cases hfalse
      have hsum_ij : ∀ c : Fin n,
          (laneVal (pts.get i') c.val + laneVal (pts.get j') c.val + laneVal (pts.get k') c.val) % 3 = 0 := by
        intro c
        have hc := hline c
        have hgi : (pts.map (decodeCapPoint n)).get i = decodeCapPoint n (pts.get i') := by simp [i']
        have hgj : (pts.map (decodeCapPoint n)).get j = decodeCapPoint n (pts.get j') := by simp [j']
        have hgk : (pts.map (decodeCapPoint n)).get k = decodeCapPoint n (pts.get k') := by simp [k']
        rw [hgi, hgj, hgk, hdecode_val _ hpi c, hdecode_val _ hpj c, hdecode_val _ hpk c] at hc
        exact hc
      by_cases hlt : i'.val < j'.val
      · exact hcheck_ordered i' j' hlt hpi hpj hsum_ij
      · have hgt : j'.val < i'.val := by omega
        exact hcheck_ordered j' i' hgt hpj hpi (fun c => by
          have := hsum_ij c; omega)

/-! ## 2. 3-AP-Free (Salem–Spencer) Sets and 3. Sidon Sets -/

/-- Check strictly increasing sequence bounded strictly below `N`. -/
def checkStrictIncAux (N : Nat) : Nat → List Nat → Bool
  | _, [] => true
  | prev, x :: xs => Nat.blt prev x && Nat.blt x N && checkStrictIncAux N x xs

def checkStrictInc (N : Nat) : List Nat → Bool
  | [] => true
  | x :: xs => Nat.blt x N && checkStrictIncAux N x xs

/-- Build bitmask of all elements in `xs`. -/
def setMask : List Nat → Nat
  | [] => 0
  | x :: xs => (1 <<< x) ||| setMask xs

/-- Check that for `a` and every `b ∈ bs`, `2 * b - a` is not set in `mask`. -/
def checkAP3Against (mask a : Nat) : List Nat → Bool
  | [] => true
  | b :: bs => !(mask.testBit (2 * b - a)) && checkAP3Against mask a bs

/-- Check that no `a < b < c` in strictly increasing `xs` satisfies `a + c = 2 * b`. -/
def checkAP3All (mask : Nat) : List Nat → Bool
  | [] => true
  | a :: rest => checkAP3Against mask a rest && checkAP3All mask rest

def checkAP3Free (N : Nat) (xs : List Nat) : Bool :=
  checkStrictInc N xs && checkAP3All (setMask xs) xs

/-- Thread pairwise positive-difference bitmask through all pairs `a < b` in `xs`. -/
def checkSidonAgainst (a : Nat) : List Nat → Nat → Option Nat
  | [], dmask => some dmask
  | b :: bs, dmask =>
    let d := b - a
    if dmask.testBit d then none
    else checkSidonAgainst a bs (dmask ||| (1 <<< d))

def checkSidonDiffs : List Nat → Nat → Option Nat
  | [], dmask => some dmask
  | a :: rest, dmask =>
    match checkSidonAgainst a rest dmask with
    | none => none
    | some dmask' => checkSidonDiffs rest dmask'

def checkSidonSet (N : Nat) (xs : List Nat) : Bool :=
  checkStrictInc N xs && (checkSidonDiffs xs 0).isSome

theorem checkStrictIncAux_sound (N prev : Nat) (xs : List Nat)
    (h : checkStrictIncAux N prev xs = true) :
    (∀ x ∈ xs, prev < x ∧ x < N) ∧
    (∀ i j : Fin xs.length, i.val < j.val → xs.get i < xs.get j) := by
  induction xs generalizing prev with
  | nil => exact ⟨(fun _ hm => nomatch hm), fun i => Fin.elim0 i⟩
  | cons x rest ih =>
    simp only [checkStrictIncAux, Bool.and_eq_true, Nat.blt_eq] at h
    rcases ih x h.2 with ⟨hmem_r, hinc_r⟩
    refine ⟨?_, ?_⟩
    · intro y hy
      rcases List.mem_cons.1 hy with rfl | hy'
      · exact h.1
      · have := hmem_r y hy'; omega
    · intro i j hij
      rcases i with ⟨iv, hilt⟩
      rcases j with ⟨jv, hjlt⟩
      dsimp only at hij
      cases iv with
      | zero =>
        cases jv with
        | zero => omega
        | succ jv =>
          exact (hmem_r (rest.get ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩) (List.get_mem _ _)).1
      | succ iv =>
        cases jv with
        | zero => omega
        | succ jv =>
          exact hinc_r ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩ ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩ (by dsimp only; omega)

theorem checkStrictInc_sound (N : Nat) (xs : List Nat) (h : checkStrictInc N xs = true) :
    (∀ x ∈ xs, x < N) ∧
    (∀ i j : Fin xs.length, i.val < j.val → xs.get i < xs.get j) := by
  cases xs with
  | nil => exact ⟨(fun _ hm => nomatch hm), fun i => Fin.elim0 i⟩
  | cons x rest =>
    simp only [checkStrictInc, Bool.and_eq_true, Nat.blt_eq] at h
    rcases checkStrictIncAux_sound N x rest h.2 with ⟨hmem_r, hinc_r⟩
    refine ⟨?_, ?_⟩
    · intro y hy
      rcases List.mem_cons.1 hy with rfl | hy'
      · exact h.1
      · exact (hmem_r y hy').2
    · intro i j hij
      rcases i with ⟨iv, hilt⟩
      rcases j with ⟨jv, hjlt⟩
      dsimp only at hij
      cases iv with
      | zero =>
        cases jv with
        | zero => omega
        | succ jv =>
          exact (hmem_r (rest.get ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩) (List.get_mem _ _)).1
      | succ iv =>
        cases jv with
        | zero => omega
        | succ jv =>
          exact hinc_r ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩ ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩ (by dsimp only; omega)

theorem setMask_testBit_of_mem (xs : List Nat) (z : Nat) (hz : z ∈ xs) :
    (setMask xs).testBit z = true := by
  induction xs with
  | nil => cases hz
  | cons x rest ih =>
    simp only [setMask, Nat.testBit_or]
    rcases List.mem_cons.1 hz with rfl | hz'
    · have hbit : (1 <<< z) = 2 ^ z := by rw [Nat.shiftLeft_eq, Nat.one_mul]
      rw [hbit, Nat.testBit_two_pow]; simp
    · rw [ih hz']; simp

theorem checkAP3Against_sound (mask a : Nat) (bs : List Nat)
    (h : checkAP3Against mask a bs = true) :
    ∀ b ∈ bs, mask.testBit (2 * b - a) = false := by
  induction bs with
  | nil => intro _ hm; cases hm
  | cons b rest ih =>
    simp only [checkAP3Against, Bool.and_eq_true, Bool.not_eq_true'] at h
    intro y hy
    rcases List.mem_cons.1 hy with rfl | hy'
    · exact h.1
    · exact ih h.2 y hy'

theorem checkAP3All_sound (mask : Nat) (xs : List Nat) (h : checkAP3All mask xs = true) :
    ∀ i j : Fin xs.length, i.val < j.val →
      mask.testBit (2 * xs.get j - xs.get i) = false := by
  induction xs with
  | nil => intro i; exact Fin.elim0 i
  | cons a rest ih =>
    simp only [checkAP3All, Bool.and_eq_true] at h
    intro i j hij
    rcases i with ⟨iv, hilt⟩
    rcases j with ⟨jv, hjlt⟩
    dsimp only at hij
    cases iv with
    | zero =>
      cases jv with
      | zero => omega
      | succ jv =>
        exact checkAP3Against_sound mask a rest h.1
          (rest.get ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩) (List.get_mem _ _)
    | succ iv =>
      cases jv with
      | zero => omega
      | succ jv =>
        exact ih h.2 ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩ ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩ (by dsimp only; omega)

/-- **End-to-end soundness for 3-AP-free (Salem–Spencer) sets**: if `xs.length = M` and
`checkAP3Free N xs = true`, then `ValidAP3Free N M`. -/
theorem validAP3Free_of_check (N M : Nat) (xs : List Nat)
    (hlen : xs.length = M) (hchk : checkAP3Free N xs = true) :
    ValidAP3Free N M := by
  simp only [checkAP3Free, Bool.and_eq_true] at hchk
  rcases checkStrictInc_sound N xs hchk.1 with ⟨hltN, hinc⟩
  have hap := checkAP3All_sound (setMask xs) xs hchk.2
  refine ⟨xs, hlen, hltN, ?_, ?_⟩
  · intro i j hij
    have hne : i.val ≠ j.val := fun h => hij (Fin.ext h)
    by_cases hlt : i.val < j.val
    · have := hinc i j hlt; omega
    · have := hinc j i (by omega); omega
  · intro a ha b hb c hc hab hbc heq
    rcases List.get_of_mem ha with ⟨ia, rfl⟩
    rcases List.get_of_mem hb with ⟨ib, rfl⟩
    have hia_lt_ib : ia.val < ib.val := by
      by_cases hlt : ia.val < ib.val
      · exact hlt
      · by_cases he : ia.val = ib.val
        · have : ia = ib := Fin.ext he; subst this; omega
        · have := hinc ib ia (by omega); omega
    have hf := hap ia ib hia_lt_ib
    have hc_eq : c = 2 * xs.get ib - xs.get ia := by omega
    rw [← hc_eq] at hf
    have ht := setMask_testBit_of_mem xs c hc
    rw [ht] at hf; cases hf

theorem checkSidonAgainst_sound (a : Nat) (bs : List Nat) (dmask res : Nat)
    (h : checkSidonAgainst a bs dmask = some res) :
    (∀ j : Fin bs.length, dmask.testBit (bs.get j - a) = false) ∧
    (∀ j1 j2 : Fin bs.length, j1 ≠ j2 → bs.get j1 - a ≠ bs.get j2 - a) ∧
    (∀ d, res.testBit d = true ↔ dmask.testBit d = true ∨ ∃ j : Fin bs.length, bs.get j - a = d) := by
  induction bs generalizing dmask with
  | nil =>
    simp only [checkSidonAgainst, Option.some.injEq] at h
    subst h
    exact ⟨(fun j => Fin.elim0 j), (fun j => Fin.elim0 j), fun d => by simp⟩
  | cons b rest ih =>
    simp only [checkSidonAgainst] at h
    split at h
    · cases h
    · next hnot =>
      have hdm0 : dmask.testBit (b - a) = false := by
        cases ht : dmask.testBit (b - a)
        · rfl
        · exact False.elim (hnot ht)
      let dmask' := dmask ||| (1 <<< (b - a))
      have hd'_tb : ∀ d, dmask'.testBit d = (dmask.testBit d || decide (b - a = d)) := by
        intro d
        have hbit : (1 <<< (b - a)) = 2 ^ (b - a) := by rw [Nat.shiftLeft_eq, Nat.one_mul]
        simp only [dmask', Nat.testBit_or, hbit, Nat.testBit_two_pow]
      rcases ih dmask' h with ⟨hfresh, huniq, hbits⟩
      refine ⟨?_, ?_, ?_⟩
      · intro j
        rcases j with ⟨jv, hjlt⟩
        cases jv with
        | zero => exact hdm0
        | succ jv =>
          have h1 := hfresh ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩
          rw [hd'_tb] at h1
          exact (Bool.or_eq_false_iff.1 h1).1
      · intro j1 j2 hne
        rcases j1 with ⟨v1, h1⟩
        rcases j2 with ⟨v2, h2⟩
        cases v1 with
        | zero =>
          cases v2 with
          | zero => exact False.elim (hne rfl)
          | succ v2 =>
            have hf := hfresh ⟨v2, Nat.lt_of_succ_lt_succ h2⟩
            rw [hd'_tb] at hf
            have := (Bool.or_eq_false_iff.1 hf).2
            exact decide_eq_false_iff_not.1 this
        | succ v1 =>
          cases v2 with
          | zero =>
            have hf := hfresh ⟨v1, Nat.lt_of_succ_lt_succ h1⟩
            rw [hd'_tb] at hf
            have := (Bool.or_eq_false_iff.1 hf).2
            exact Ne.symm (decide_eq_false_iff_not.1 this)
          | succ v2 =>
            exact huniq ⟨v1, Nat.lt_of_succ_lt_succ h1⟩ ⟨v2, Nat.lt_of_succ_lt_succ h2⟩
              (fun heq => hne (Fin.ext (by have := congrArg Fin.val heq; dsimp only at this ⊢; omega)))
      · intro d
        rw [hbits d, hd'_tb d]
        constructor
        · intro hd
          rcases hd with h1 | ⟨j, hj⟩
          · rcases Bool.or_eq_true_iff.1 h1 with hdm | heq
            · exact Or.inl hdm
            · exact Or.inr ⟨⟨0, by simp⟩, of_decide_eq_true heq⟩
          · exact Or.inr ⟨⟨j.val + 1, Nat.succ_lt_succ j.isLt⟩, hj⟩
        · intro hd
          rcases hd with hdm | ⟨⟨jv, hjlt⟩, hj⟩
          · exact Or.inl (by simp [hdm])
          · cases jv with
            | zero =>
              change b - a = d at hj
              exact Or.inl (by simp [hj])
            | succ jv => exact Or.inr ⟨⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩, hj⟩

theorem checkSidonDiffs_sound (xs : List Nat) (dmask res : Nat)
    (h : checkSidonDiffs xs dmask = some res) :
    (∀ i j : Fin xs.length, i.val < j.val → dmask.testBit (xs.get j - xs.get i) = false) ∧
    (∀ i1 j1 i2 j2 : Fin xs.length, i1.val < j1.val → i2.val < j2.val →
      xs.get j1 - xs.get i1 = xs.get j2 - xs.get i2 → i1 = i2 ∧ j1 = j2) := by
  induction xs generalizing dmask with
  | nil => exact ⟨(fun i => Fin.elim0 i), fun i => Fin.elim0 i⟩
  | cons a rest ih =>
    simp only [checkSidonDiffs] at h
    cases h1 : checkSidonAgainst a rest dmask with
    | none => rw [h1] at h; cases h
    | some dmask' =>
      rw [h1] at h
      rcases checkSidonAgainst_sound a rest dmask dmask' h1 with ⟨ha_fresh, ha_uniq, ha_bits⟩
      rcases ih dmask' h with ⟨hr_fresh, hr_uniq⟩
      refine ⟨?_, ?_⟩
      · intro i j hij
        rcases i with ⟨iv, hilt⟩
        rcases j with ⟨jv, hjlt⟩
        dsimp only at hij
        cases iv with
        | zero =>
          cases jv with
          | zero => omega
          | succ jv => exact ha_fresh ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩
        | succ iv =>
          cases jv with
          | zero => omega
          | succ jv =>
            have hf := hr_fresh ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩ ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩ (by dsimp only; omega)
            cases hdm : dmask.testBit (rest.get ⟨jv, Nat.lt_of_succ_lt_succ hjlt⟩ - rest.get ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩)
            · exact hdm
            · have ht := (ha_bits _).2 (Or.inl hdm)
              rw [ht] at hf; cases hf
      · intro i1 j1 i2 j2 hlt1 hlt2 heq
        rcases i1 with ⟨v1, hi1⟩
        rcases j1 with ⟨w1, hj1⟩
        rcases i2 with ⟨v2, hi2⟩
        rcases j2 with ⟨w2, hj2⟩
        dsimp only at hlt1 hlt2
        cases v1 with
        | zero =>
          cases w1 with
          | zero => omega
          | succ w1 =>
            cases v2 with
            | zero =>
              cases w2 with
              | zero => omega
              | succ w2 =>
                by_cases hw_eq : w1 = w2
                · subst hw_eq; exact ⟨rfl, rfl⟩
                · exact False.elim (ha_uniq ⟨w1, Nat.lt_of_succ_lt_succ hj1⟩ ⟨w2, Nat.lt_of_succ_lt_succ hj2⟩
                    (fun hw => hw_eq (congrArg Fin.val hw)) heq)
            | succ v2 =>
              cases w2 with
              | zero => omega
              | succ w2 =>
                have hf := hr_fresh ⟨v2, Nat.lt_of_succ_lt_succ hi2⟩ ⟨w2, Nat.lt_of_succ_lt_succ hj2⟩ (by dsimp only; omega)
                have ht : dmask'.testBit (rest.get ⟨w2, Nat.lt_of_succ_lt_succ hj2⟩ - rest.get ⟨v2, Nat.lt_of_succ_lt_succ hi2⟩) = true :=
                  (ha_bits _).2 (Or.inr ⟨⟨w1, Nat.lt_of_succ_lt_succ hj1⟩, heq⟩)
                rw [ht] at hf; cases hf
        | succ v1 =>
          cases w1 with
          | zero => omega
          | succ w1 =>
            cases v2 with
            | zero =>
              cases w2 with
              | zero => omega
              | succ w2 =>
                have hf := hr_fresh ⟨v1, Nat.lt_of_succ_lt_succ hi1⟩ ⟨w1, Nat.lt_of_succ_lt_succ hj1⟩ (by dsimp only; omega)
                have ht : dmask'.testBit (rest.get ⟨w1, Nat.lt_of_succ_lt_succ hj1⟩ - rest.get ⟨v1, Nat.lt_of_succ_lt_succ hi1⟩) = true :=
                  (ha_bits _).2 (Or.inr ⟨⟨w2, Nat.lt_of_succ_lt_succ hj2⟩, heq.symm⟩)
                rw [ht] at hf; cases hf
            | succ v2 =>
              cases w2 with
              | zero => omega
              | succ w2 =>
                rcases hr_uniq ⟨v1, Nat.lt_of_succ_lt_succ hi1⟩ ⟨w1, Nat.lt_of_succ_lt_succ hj1⟩
                    ⟨v2, Nat.lt_of_succ_lt_succ hi2⟩ ⟨w2, Nat.lt_of_succ_lt_succ hj2⟩
                    (by dsimp only; omega) (by dsimp only; omega) heq with ⟨hv, hw⟩
                exact ⟨Fin.ext (by have := congrArg Fin.val hv; dsimp only at this ⊢; omega),
                       Fin.ext (by have := congrArg Fin.val hw; dsimp only at this ⊢; omega)⟩

/-- **End-to-end soundness for Sidon (`B_2`) sets**: if `xs.length = M` and
`checkSidonSet N xs = true`, then `ValidSidonSet N M`. -/
theorem validSidonSet_of_check (N M : Nat) (xs : List Nat)
    (hlen : xs.length = M) (hchk : checkSidonSet N xs = true) :
    ValidSidonSet N M := by
  simp only [checkSidonSet, Bool.and_eq_true] at hchk
  rcases checkStrictInc_sound N xs hchk.1 with ⟨hltN, hinc⟩
  cases hsd : checkSidonDiffs xs 0 with
  | none => rw [hsd] at hchk; simp at hchk
  | some res =>
    have huniq := (checkSidonDiffs_sound xs 0 res hsd).2
    refine ⟨xs, hlen, hltN, ?_, ?_⟩
    · intro i j hij
      have hne : i.val ≠ j.val := fun h => hij (Fin.ext h)
      by_cases hlt : i.val < j.val
      · have := hinc i j hlt; omega
      · have := hinc j i (by omega); omega
    · intro a ha b hb c hc d hd hab hcd hsum
      rcases List.get_of_mem ha with ⟨ia, rfl⟩
      rcases List.get_of_mem hb with ⟨ib, rfl⟩
      rcases List.get_of_mem hc with ⟨ic, rfl⟩
      rcases List.get_of_mem hd with ⟨id, rfl⟩
      have idx_lt : ∀ p q : Fin xs.length, xs.get p < xs.get q → p.val < q.val := by
        intro p q hpq
        by_cases hlt : p.val < q.val
        · exact hlt
        · by_cases he : p.val = q.val
          · have : p = q := Fin.ext he; subst this; omega
          · have := hinc q p (by omega); omega
      by_cases hac : xs.get ia = xs.get ic
      · exact ⟨hac, by omega⟩
      · by_cases hlt : xs.get ia < xs.get ic
        · have hdb : xs.get id < xs.get ib := by omega
          have h1 : ia.val < ic.val := idx_lt ia ic hlt
          have h2 : id.val < ib.val := idx_lt id ib hdb
          have hdiff : xs.get ic - xs.get ia = xs.get ib - xs.get id := by omega
          rcases huniq ia ic id ib h1 h2 hdiff with ⟨hai, _⟩
          subst hai; omega
        · have hca : xs.get ic < xs.get ia := by omega
          have hbd : xs.get ib < xs.get id := by omega
          have h1 : ic.val < ia.val := idx_lt ic ia hca
          have h2 : ib.val < id.val := idx_lt ib id hbd
          have hdiff : xs.get ia - xs.get ic = xs.get id - xs.get ib := by omega
          rcases huniq ic ia ib id h1 h2 hdiff with ⟨hci, _⟩
          subst hci; omega

end AdditiveComb
