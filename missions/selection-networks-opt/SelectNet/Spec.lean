/-!
# Optimal Median Selection Networks: Zero-One Principle and Bit-Sliced Kernel Evaluator

This module formalizes comparator median-selection networks on `n` wires in pure
Lean 4.36.0 (zero Mathlib, standard axioms only):

1. General linear-order comparator network semantics (`IsLinearOrder`, `applyComp`, `applyNet`).
2. Order-statistic semantics (`IsOrderStat`, `IsMedianOutput`) over every decidable linear
   order `(α, le)`:
   - For odd `n = 2m + 1`: wire `m` outputs the exact `m`-th order statistic (the median).
   - For even `n = 2m + 2`: wires `m` and `m + 1` output the unordered central pair
     `{cmpMin, cmpMax}` equal to the `m`-th and `(m + 1)`-th order statistics, matching
     Bert Dobbelaere's SorterHunter `median_networks.html` specification verbatim.
3. A complete, sorry-free proof of **Knuth's Zero-One Principle for Median Selection Networks**
   (`zero_one_principle_median`): if a comparator network selects the median on all `2^n`
   Boolean vectors, it selects the median on every input vector over every linear order `(α, le)`.
4. A fast `O(n^2)` bit-sliced DP threshold-mask generator (`popGeMask`) and `2^n`-bit parallel
   network evaluator (`checkMedianNet`) with complete soundness proof (`validMedianNetwork_of_check`).

Upstream median selection network records are pinned to Bert Dobbelaere's
`bertdobbelaere/SorterHunter` at commit `3d8b3454bad15062f4b0030052f12d6550f8d89d` (MIT),
including `median_networks.html` and `Networks/Median/Median_{7..16}_*.json`.
-/

namespace SelectNet

/-! ## Comparator networks and general linear-order semantics -/

/-- A decidable total preorder (linear order) on `α` given by `le : α → α → Bool`. -/
structure IsLinearOrder {α : Type} (le : α → α → Bool) : Prop where
  refl : ∀ x, le x x = true
  trans : ∀ x y z, le x y = true → le y z = true → le x z = true
  total : ∀ x y, le x y = true ∨ le y x = true

/-- Check that every comparator `(i, j)` acts on valid ordered wires `i < j < n`. -/
def wellFormed (n : Nat) : List (Nat × Nat) → Bool
  | [] => true
  | (i, j) :: rest => (decide (i < j) && decide (j < n)) && wellFormed n rest

def cmpMin {α : Type} (le : α → α → Bool) (a b : α) : α :=
  if le a b then a else b

def cmpMax {α : Type} (le : α → α → Bool) (a b : α) : α :=
  if le a b then b else a

def applyComp {α : Type} {n : Nat} (le : α → α → Bool) (i j : Nat) (v : Fin n → α) : Fin n → α :=
  if h : i < j ∧ j < n then
    let a := v ⟨i, Nat.lt_trans h.1 h.2⟩
    let b := v ⟨j, h.2⟩
    fun k =>
      if k.val = i then cmpMin le a b
      else if k.val = j then cmpMax le a b
      else v k
  else v

def applyNet {α : Type} {n : Nat} (le : α → α → Bool) :
    List (Nat × Nat) → (Fin n → α) → (Fin n → α)
  | [], v => v
  | (i, j) :: rest, v => applyNet le rest (applyComp le i j v)

def leBool (a b : Bool) : Bool := !a || b

def applyNetBool {n : Nat} (net : List (Nat × Nat)) (v : Fin n → Bool) : Fin n → Bool :=
  applyNet leBool net v

theorem cmpMin_leBool (a b : Bool) : cmpMin leBool a b = (a && b) := by
  cases a <;> cases b <;> rfl

theorem cmpMax_leBool (a b : Bool) : cmpMax leBool a b = (a || b) := by
  cases a <;> cases b <;> rfl

/-! ## Order-statistic and median semantics over arbitrary linear orders -/

/-- Count how many indices `i < k` satisfy `p ⟨i, _⟩ = true`. -/
def countTrueAux {n : Nat} (p : Fin n → Bool) : (k : Nat) → k ≤ n → Nat
  | 0, _ => 0
  | k + 1, hk => countTrueAux p k (Nat.le_of_succ_le hk) + (if p ⟨k, hk⟩ then 1 else 0)

def countTrue (n : Nat) (p : Fin n → Bool) : Nat :=
  countTrueAux p n (Nat.le_refl n)

theorem countTrueAux_compl {n : Nat} (p : Fin n → Bool) (k : Nat) (hk : k ≤ n) :
    countTrueAux p k hk + countTrueAux (fun i => !(p i)) k hk = k := by
  induction k with
  | zero => rfl
  | succ k ih =>
    have hrec := ih (Nat.le_of_succ_le hk)
    simp only [countTrueAux]
    by_cases hp : p ⟨k, hk⟩ = true <;> simp [hp] <;> omega

theorem countTrue_compl {n : Nat} (p : Fin n → Bool) :
    countTrue n p + countTrue n (fun i => !(p i)) = n :=
  countTrueAux_compl p n (Nat.le_refl n)

/-- `y` is an `r`-th order statistic (0-indexed) of `v : Fin n → α` under `(α, le)`:
at least `r + 1` entries of `v` are `≤ y` and at least `n - r` entries of `v` are `≥ y`. -/
def IsOrderStat {α : Type} {n : Nat} (le : α → α → Bool) (r : Nat) (v : Fin n → α) (y : α) : Prop :=
  r + 1 ≤ countTrue n (fun i => le (v i) y) ∧
  n - r ≤ countTrue n (fun i => le y (v i))

/-- Median-output condition on wire vector `out : Fin n → α` for input `v : Fin n → α`:
- For odd `n = 2m + 1`: wire `m` is the `m`-th order statistic (exact median).
- For even `n = 2m + 2`: `{min(out m, out (m + 1)), max(out m, out (m + 1))}` are the
  `m`-th and `(m + 1)`-th order statistics (unordered central pair, matching SorterHunter). -/
def IsMedianOutput {α : Type} {n : Nat} (le : α → α → Bool) (v out : Fin n → α) : Prop :=
  if h : n = 0 then True
  else
    let m := (n - 1) / 2
    if hodd : n % 2 = 1 then
      IsOrderStat le m v (out ⟨m, by omega⟩)
    else
      let a := out ⟨m, by omega⟩
      let b := out ⟨m + 1, by omega⟩
      IsOrderStat le m v (cmpMin le a b) ∧ IsOrderStat le (m + 1) v (cmpMax le a b)

/-- Boolean median specification:
- Odd `n = 2m + 1`: wire `m` is `true` iff input has `≥ m + 1` ones.
- Even `n = 2m + 2`: `out m && out (m + 1)` is `true` iff input has `≥ m + 2` ones,
  and `out m || out (m + 1)` is `true` iff input has `≥ m + 1` ones. -/
def IsBoolMedian {n : Nat} (v out : Fin n → Bool) : Prop :=
  if h : n = 0 then True
  else
    let m := (n - 1) / 2
    if hodd : n % 2 = 1 then
      out ⟨m, by omega⟩ = decide (m + 1 ≤ countTrue n v)
    else
      (out ⟨m, by omega⟩ && out ⟨m + 1, by omega⟩) = decide (m + 2 ≤ countTrue n v) ∧
      (out ⟨m, by omega⟩ || out ⟨m + 1, by omega⟩) = decide (m + 1 ≤ countTrue n v)

/-! ## Knuth's Zero-One Principle for Median Selection Networks -/

/-- Any monotone map `f : α → Bool` (`le a b = true → leBool (f a) (f b) = true`) commutes
with `cmpMin`, `cmpMax`, and `applyNet`. -/
def IsMonotone {α : Type} (le : α → α → Bool) (f : α → Bool) : Prop :=
  ∀ a b, le a b = true → leBool (f a) (f b) = true

theorem mono_cmpMin {α : Type} (le : α → α → Bool) (hlo : IsLinearOrder le)
    (f : α → Bool) (hf : IsMonotone le f) (a b : α) :
    f (cmpMin le a b) = (f a && f b) := by
  unfold cmpMin
  cases hab : le a b
  · have hba : le b a = true := by
      rcases hlo.total a b with h | h
      · rw [hab] at h; cases h
      · exact h
    have hfb := hf b a hba
    cases hfa : f a <;> cases hfb' : f b <;> simp_all [leBool]
  · have hfa := hf a b hab
    cases hfa' : f a <;> cases hfb : f b <;> simp_all [leBool]

theorem mono_cmpMax {α : Type} (le : α → α → Bool) (hlo : IsLinearOrder le)
    (f : α → Bool) (hf : IsMonotone le f) (a b : α) :
    f (cmpMax le a b) = (f a || f b) := by
  unfold cmpMax
  cases hab : le a b
  · have hba : le b a = true := by
      rcases hlo.total a b with h | h
      · rw [hab] at h; cases h
      · exact h
    have hfb := hf b a hba
    cases hfa : f a <;> cases hfb' : f b <;> simp_all [leBool]
  · have hfa := hf a b hab
    cases hfa' : f a <;> cases hfb : f b <;> simp_all [leBool]

theorem applyComp_ext {α : Type} {n : Nat} (le : α → α → Bool) (i j : Nat)
    {v₁ v₂ : Fin n → α} (h : ∀ k, v₁ k = v₂ k) :
    ∀ k, applyComp le i j v₁ k = applyComp le i j v₂ k := by
  intro k; unfold applyComp; split
  · simp only [h]
  · exact h k

theorem applyNet_ext {α : Type} {n : Nat} (le : α → α → Bool) (net : List (Nat × Nat))
    {v₁ v₂ : Fin n → α} (h : ∀ k, v₁ k = v₂ k) :
    ∀ k, applyNet le net v₁ k = applyNet le net v₂ k := by
  induction net generalizing v₁ v₂ with
  | nil => exact h
  | cons c rest ih => rcases c with ⟨i, j⟩; exact ih (applyComp_ext le i j h)

theorem mono_applyComp {α : Type} {n : Nat} (le : α → α → Bool) (hlo : IsLinearOrder le)
    (f : α → Bool) (hf : IsMonotone le f) (i j : Nat) (v : Fin n → α) (k : Fin n) :
    f (applyComp le i j v k) = applyComp leBool i j (fun idx => f (v idx)) k := by
  unfold applyComp
  split
  · dsimp only
    split
    · rw [cmpMin_leBool]; exact mono_cmpMin le hlo f hf _ _
    · split
      · rw [cmpMax_leBool]; exact mono_cmpMax le hlo f hf _ _
      · rfl
  · rfl

theorem mono_applyNet {α : Type} {n : Nat} (le : α → α → Bool) (hlo : IsLinearOrder le)
    (f : α → Bool) (hf : IsMonotone le f) (net : List (Nat × Nat)) (v : Fin n → α) :
    ∀ k, f (applyNet le net v k) = applyNetBool net (fun idx => f (v idx)) k := by
  induction net generalizing v with
  | nil => intro k; rfl
  | cons c rest ih =>
    rcases c with ⟨i, j⟩
    intro k
    simp only [applyNet, applyNetBool]
    rw [ih (applyComp le i j v) k]
    exact applyNet_ext leBool rest (mono_applyComp le hlo f hf i j v) k

/-- Open threshold `x ↦ !(le x t)` is monotone. -/
theorem isMonotone_threshGt {α : Type} (le : α → α → Bool) (hlo : IsLinearOrder le) (t : α) :
    IsMonotone le (fun x => !(le x t)) := by
  intro a b hab
  cases hat : le a t <;> cases hbt : le b t
  · simp [leBool, hat, hbt]
  · exfalso
    have := hlo.trans a b t hab hbt
    rw [hat] at this; cases this
  · simp [leBool, hat, hbt]
  · simp [leBool, hat, hbt]

/-- Closed threshold `x ↦ le t x` is monotone. -/
theorem isMonotone_threshGe {α : Type} (le : α → α → Bool) (hlo : IsLinearOrder le) (t : α) :
    IsMonotone le (fun x => le t x) := by
  intro a b hab
  cases hta : le t a <;> cases htb : le t b
  · simp [leBool, hta, htb]
  · simp [leBool, hta, htb]
  · exfalso
    have := hlo.trans t a b hta hab
    rw [htb] at this; cases this
  · simp [leBool, hta, htb]

/-- **Knuth's Zero-One Principle for Median Selection Networks**:
if `net` selects the median on all `2^n` Boolean vectors, then `net` selects the exact median
(odd `n`) or unordered central pair (even `n`) over every decidable linear order `(α, le)`. -/
theorem zero_one_principle_median {n : Nat} (net : List (Nat × Nat))
    (hbool : ∀ v : Fin n → Bool, IsBoolMedian v (applyNetBool net v)) :
    ∀ {α : Type} (le : α → α → Bool), IsLinearOrder le →
      ∀ v : Fin n → α, IsMedianOutput le v (applyNet le net v) := by
  intro α le hlo v
  unfold IsMedianOutput
  by_cases hn0 : n = 0
  · simp [hn0]
  · simp only [hn0, ↓reduceDIte]
    let m := (n - 1) / 2
    by_cases hodd : n % 2 = 1
    · simp only [hodd, ↓reduceDIte]
      let y := applyNet le net v ⟨m, by omega⟩
      have hgt := hbool (fun i => !(le (v i) y))
      unfold IsBoolMedian at hgt
      simp only [hn0, hodd, ↓reduceDIte] at hgt
      have hy_gt : applyNetBool net (fun i => !(le (v i) y)) ⟨m, by omega⟩ = false := by
        rw [← mono_applyNet le hlo (fun x => !(le x y)) (isMonotone_threshGt le hlo y) net v ⟨m, by omega⟩]
        simp [y, hlo.refl]
      rw [hy_gt] at hgt
      have hcnt_gt : ¬ (m + 1 ≤ countTrue n (fun i => !(le (v i) y))) :=
        decide_eq_false_iff_not.1 hgt.symm
      have hcompl := countTrue_compl (fun i => le (v i) y)
      have hge := hbool (fun i => le y (v i))
      unfold IsBoolMedian at hge
      simp only [hn0, hodd, ↓reduceDIte] at hge
      have hy_ge : applyNetBool net (fun i => le y (v i)) ⟨m, by omega⟩ = true := by
        rw [← mono_applyNet le hlo (fun x => le y x) (isMonotone_threshGe le hlo y) net v ⟨m, by omega⟩]
        exact hlo.refl y
      rw [hy_ge] at hge
      have hcnt_ge : m + 1 ≤ countTrue n (fun i => le y (v i)) :=
        of_decide_eq_true hge.symm
      exact ⟨by dsimp only [y, m] at hcompl hcnt_gt; omega,
             by dsimp only [y, m] at hcnt_ge; omega⟩
    · simp only [hodd, ↓reduceDIte]
      let a := applyNet le net v ⟨m, by omega⟩
      let b := applyNet le net v ⟨m + 1, by omega⟩
      let ylo := cmpMin le a b
      let yhi := cmpMax le a b
      constructor
      · -- ylo is m-th order statistic
        have hgt := hbool (fun i => !(le (v i) ylo))
        unfold IsBoolMedian at hgt
        simp only [hn0, hodd, ↓reduceDIte] at hgt
        have h1 : (applyNetBool net (fun i => !(le (v i) ylo)) ⟨m, by omega⟩ &&
            applyNetBool net (fun i => !(le (v i) ylo)) ⟨m + 1, by omega⟩) = false := by
          rw [← mono_applyNet le hlo _ (isMonotone_threshGt le hlo ylo) net v ⟨m, by omega⟩,
              ← mono_applyNet le hlo _ (isMonotone_threshGt le hlo ylo) net v ⟨m + 1, by omega⟩,
              ← mono_cmpMin le hlo _ (isMonotone_threshGt le hlo ylo) a b]
          simp [ylo, hlo.refl]
        rw [h1] at hgt
        have hcnt_gt : ¬ (m + 2 ≤ countTrue n (fun i => !(le (v i) ylo))) :=
          decide_eq_false_iff_not.1 hgt.1.symm
        have hcompl := countTrue_compl (fun i => le (v i) ylo)
        have hge := hbool (fun i => le ylo (v i))
        unfold IsBoolMedian at hge
        simp only [hn0, hodd, ↓reduceDIte] at hge
        have h2 : (applyNetBool net (fun i => le ylo (v i)) ⟨m, by omega⟩ &&
            applyNetBool net (fun i => le ylo (v i)) ⟨m + 1, by omega⟩) = true := by
          rw [← mono_applyNet le hlo _ (isMonotone_threshGe le hlo ylo) net v ⟨m, by omega⟩,
              ← mono_applyNet le hlo _ (isMonotone_threshGe le hlo ylo) net v ⟨m + 1, by omega⟩,
              ← mono_cmpMin le hlo _ (isMonotone_threshGe le hlo ylo) a b]
          exact hlo.refl ylo
        rw [h2] at hge
        have hcnt_ge : m + 2 ≤ countTrue n (fun i => le ylo (v i)) :=
          of_decide_eq_true hge.1.symm
        exact ⟨by dsimp only [ylo, a, b, m] at hcompl hcnt_gt; omega,
               by dsimp only [ylo, a, b, m] at hcnt_ge; omega⟩
      · -- yhi is (m + 1)-th order statistic
        have hgt := hbool (fun i => !(le (v i) yhi))
        unfold IsBoolMedian at hgt
        simp only [hn0, hodd, ↓reduceDIte] at hgt
        have h1 : (applyNetBool net (fun i => !(le (v i) yhi)) ⟨m, by omega⟩ ||
            applyNetBool net (fun i => !(le (v i) yhi)) ⟨m + 1, by omega⟩) = false := by
          rw [← mono_applyNet le hlo _ (isMonotone_threshGt le hlo yhi) net v ⟨m, by omega⟩,
              ← mono_applyNet le hlo _ (isMonotone_threshGt le hlo yhi) net v ⟨m + 1, by omega⟩,
              ← mono_cmpMax le hlo _ (isMonotone_threshGt le hlo yhi) a b]
          simp [yhi, hlo.refl]
        rw [h1] at hgt
        have hcnt_gt : ¬ (m + 1 ≤ countTrue n (fun i => !(le (v i) yhi))) :=
          decide_eq_false_iff_not.1 hgt.2.symm
        have hcompl := countTrue_compl (fun i => le (v i) yhi)
        have hge := hbool (fun i => le yhi (v i))
        unfold IsBoolMedian at hge
        simp only [hn0, hodd, ↓reduceDIte] at hge
        have h2 : (applyNetBool net (fun i => le yhi (v i)) ⟨m, by omega⟩ ||
            applyNetBool net (fun i => le yhi (v i)) ⟨m + 1, by omega⟩) = true := by
          rw [← mono_applyNet le hlo _ (isMonotone_threshGe le hlo yhi) net v ⟨m, by omega⟩,
              ← mono_applyNet le hlo _ (isMonotone_threshGe le hlo yhi) net v ⟨m + 1, by omega⟩,
              ← mono_cmpMax le hlo _ (isMonotone_threshGe le hlo yhi) a b]
          exact hlo.refl yhi
        rw [h2] at hge
        have hcnt_ge : m + 1 ≤ countTrue n (fun i => le yhi (v i)) :=
          of_decide_eq_true hge.2.symm
        exact ⟨by dsimp only [yhi, a, b, m] at hcompl hcnt_gt; omega,
               by dsimp only [yhi, a, b, m] at hcnt_ge; omega⟩

/-! ## Mission target predicate -/

/-- Existence of a well-formed comparator network on `n` wires with `k` comparators that
selects the median (odd `n`) or unordered central pair (even `n`) over every decidable
linear order `(α, le)`. -/
def ValidMedianNetwork (n k : Nat) : Prop :=
  ∃ net : List (Nat × Nat),
    wellFormed n net = true ∧
    net.length = k ∧
    ∀ {α : Type} (le : α → α → Bool), IsLinearOrder le →
      ∀ v : Fin n → α, IsMedianOutput le v (applyNet le net v)

/-! ## Fast O(n^2) bit-sliced threshold DP and parallel network evaluator -/

def repMask : Nat → Nat → Nat → Nat
  | 0, _, x => x
  | k + 1, step, x => repMask k (step * 2) (x ||| (x <<< step))

def wireMask (n b : Nat) : Nat :=
  let half := 1 <<< b
  let block := ((1 <<< half) - 1) <<< half
  repMask (n - b - 1) (2 * half) block

def initWiresBits (n : Nat) : List Nat :=
  (List.range n).map (wireMask n)

def getWire : List Nat → Nat → Nat
  | [], _ => 0
  | x :: _, 0 => x
  | _ :: xs, i + 1 => getWire xs i

def setWire : List Nat → Nat → Nat → List Nat
  | [], _, _ => []
  | _ :: xs, 0, v => v :: xs
  | x :: xs, i + 1, v => x :: setWire xs i v

def evalNetBits (w : List Nat) : List (Nat × Nat) → List Nat
  | [] => w
  | (i, j) :: rest =>
    let a := getWire w i
    let b := getWire w j
    evalNetBits (setWire (setWire w i (a &&& b)) j (a ||| b)) rest

/-- One DP update step adding wire mask `w` to the table `dp` where `dp[k]` is the bitmask
of inputs having `≥ k` ones among wires processed so far. -/
def popStepAux (w : Nat) : Nat → List Nat → List Nat
  | prev, [] => [prev &&& w]
  | prev, cur :: rest => (cur ||| (prev &&& w)) :: popStepAux w cur rest

def popStep (w : Nat) : List Nat → List Nat
  | [] => []
  | d0 :: rest => d0 :: popStepAux w d0 rest

def popTableFold : List Nat → List Nat → List Nat
  | [], dp => dp
  | w :: ws, dp => popTableFold ws (popStep w dp)

/-- Compute the bit-sliced threshold table `dp` for `n` wires in `O(n^2)` bitwise ops:
`getWire (popGeTable n) k` has bit `m` (`m < 2^n`) equal to `decide (k ≤ popcount_n m)`. -/
def popGeTable (n : Nat) : List Nat :=
  popTableFold (initWiresBits n) [(1 <<< (1 <<< n)) - 1]

/-- Kernel-decidable bit-sliced median-network verifier testing all `2^n` Boolean inputs in parallel. -/
def checkMedianNet (n : Nat) (net : List (Nat × Nat)) : Bool :=
  if n == 0 then true
  else
    let init := initWiresBits n
    let out := evalNetBits init net
    let tbl := popTableFold init [(1 <<< (1 <<< n)) - 1]
    let m := (n - 1) / 2
    if n % 2 == 1 then
      getWire out m == getWire tbl (m + 1)
    else
      let wm := getWire out m
      let wm1 := getWire out (m + 1)
      ((wm &&& wm1) == getWire tbl (m + 2)) && ((wm ||| wm1) == getWire tbl (m + 1))

/-! ## Bit-sliced evaluator and DP soundness proofs -/

theorem repMask_testBit (k step x : Nat) (hstep : 0 < step)
    (hhi : ∀ r, step ≤ r → x.testBit r = false) :
    (∀ m, m < step * 2 ^ k → (repMask k step x).testBit m = x.testBit (m % step)) ∧
    (∀ m, step * 2 ^ k ≤ m → (repMask k step x).testBit m = false) := by
  induction k generalizing step x with
  | zero =>
    constructor
    · intro m hm; simp only [Nat.pow_zero, Nat.mul_one] at hm; simp [repMask, Nat.mod_eq_of_lt hm]
    · intro m hm; simp only [Nat.pow_zero, Nat.mul_one] at hm; exact hhi m hm
  | succ k ih =>
    have hstep2 : 0 < step * 2 := by omega
    have hhi' : ∀ r, step * 2 ≤ r → (x ||| (x <<< step)).testBit r = false := by
      intro r hr; rw [Nat.testBit_or, Nat.testBit_shiftLeft]
      simp [hhi r (by omega), hhi (r - step) (by omega)]
    have hpow : step * 2 * 2 ^ k = step * 2 ^ (k + 1) := by
      rw [Nat.pow_succ, Nat.mul_assoc, Nat.mul_comm 2 (2 ^ k)]
    rcases ih (step * 2) (x ||| (x <<< step)) hstep2 hhi' with ⟨hlo, hge⟩
    constructor
    · intro m hm
      rw [repMask, hlo m (by rw [hpow]; exact hm)]
      let r := m % (step * 2)
      have hrlt : r < step * 2 := Nat.mod_lt m hstep2
      have hmod : r % step = m % step := Nat.mod_mod_of_dvd m (Nat.dvd_mul_right step 2)
      rw [Nat.testBit_or, Nat.testBit_shiftLeft]
      by_cases hlt : r < step
      · rw [decide_eq_false (by omega)]; simp only [Bool.false_and, Bool.or_false]
        rw [← hmod, Nat.mod_eq_of_lt hlt]
      · rw [hhi r (by omega), decide_eq_true (by omega)]; simp only [Bool.false_or, Bool.true_and]
        have hsub : r - step = r % step := by
          have hlt2 : r - step < step := by omega
          have hr_eq : r = (r - step) + step := by omega
          have hmr : r % step = ((r - step) + step) % step := congrArg (· % step) hr_eq
          rw [Nat.add_mod_right, Nat.mod_eq_of_lt hlt2] at hmr
          exact hmr.symm
        rw [hsub, hmod]
    · intro m hm; rw [repMask]; exact hge m (by rw [hpow]; exact hm)

theorem wireMask_testBit (n b m : Nat) (hb : b < n) (hm : m < 2 ^ n) :
    (wireMask n b).testBit m = m.testBit b := by
  unfold wireMask
  have hhalf : (1 <<< b) = 2 ^ b := by rw [Nat.shiftLeft_eq, Nat.one_mul]
  have h2half : 2 * (1 <<< b) = 2 ^ (b + 1) := by rw [hhalf, Nat.pow_succ, Nat.mul_comm]
  have hpow : 2 * (1 <<< b) * 2 ^ (n - b - 1) = 2 ^ n := by rw [h2half, ← Nat.pow_add]; congr 1; omega
  have hstep_pos : 0 < 2 * (1 <<< b) := by rw [h2half]; exact Nat.two_pow_pos (b + 1)
  have hblock_hi : ∀ r, 2 * (1 <<< b) ≤ r → (((1 <<< (1 <<< b)) - 1) <<< (1 <<< b)).testBit r = false := by
    intro r hr; rw [Nat.testBit_shiftLeft]
    simp only [Nat.shiftLeft_eq, Nat.one_mul, Nat.testBit_two_pow_sub_one]
    rw [hhalf] at hr; simp [show ¬ (r - 2 ^ b < 2 ^ b) by omega]
  have hrep := (repMask_testBit (n - b - 1) (2 * (1 <<< b))
    (((1 <<< (1 <<< b)) - 1) <<< (1 <<< b)) hstep_pos hblock_hi).1 m (by rw [hpow]; exact hm)
  rw [hrep, Nat.testBit_shiftLeft]
  simp only [Nat.shiftLeft_eq, Nat.one_mul, Nat.testBit_two_pow_sub_one]
  let r := m % (2 * 2 ^ b)
  have hrlt : r < 2 * 2 ^ b := by show m % (2 * 2 ^ b) < 2 * 2 ^ b; rw [← hhalf]; exact Nat.mod_lt m hstep_pos
  have hmod_tb : r.testBit b = m.testBit b := by
    show (m % (2 * 2 ^ b)).testBit b = m.testBit b
    rw [← hhalf, h2half, Nat.testBit_mod_two_pow]; simp
  rw [← hmod_tb]
  change (decide (r ≥ 2 ^ b) && decide (r - 2 ^ b < 2 ^ b)) = r.testBit b
  rw [Nat.testBit_eq_decide_div_mod_eq]
  by_cases hlt : r < 2 ^ b
  · simp [decide_eq_false (by omega : ¬ (r ≥ 2 ^ b)), Nat.div_eq_of_lt hlt]
  · have hpos : 0 < 2 ^ b := Nat.two_pow_pos b
    have hlo : 1 ≤ r / 2 ^ b := (Nat.le_div_iff_mul_le hpos).2 (by omega)
    have hhi : r / 2 ^ b < 2 := (Nat.div_lt_iff_lt_mul hpos).2 (by omega)
    have hdiv : r / 2 ^ b = 1 := by omega
    simp [decide_eq_true (by omega : r ≥ 2 ^ b), decide_eq_true (by omega : r - 2 ^ b < 2 ^ b), hdiv]

theorem getWire_eq_getD (w : List Nat) (i : Nat) : getWire w i = w.getD i 0 := by
  induction w generalizing i with
  | nil => simp [getWire]
  | cons x xs ih => cases i with | zero => rfl | succ i => exact ih i

theorem length_setWire (w : List Nat) (i v : Nat) : (setWire w i v).length = w.length := by
  induction w generalizing i with
  | nil => rfl
  | cons _ _ ih => cases i with | zero => rfl | succ i => simp [setWire, ih]

theorem getWire_setWire (w : List Nat) (i v k : Nat) (hi : i < w.length) :
    getWire (setWire w i v) k = if k = i then v else getWire w k := by
  induction w generalizing i k with
  | nil => cases hi
  | cons x xs ih =>
    cases i with
    | zero => cases k with | zero => rfl | succ k => simp [setWire, getWire]
    | succ i =>
      cases k with
      | zero => simp [setWire, getWire]
      | succ k =>
        simp only [setWire, getWire]; rw [ih i k (Nat.lt_of_succ_lt_succ hi)]
        by_cases hki : k = i
        · subst hki; simp
        · simp [hki]

theorem evalNetBits_testBit {n : Nat} (net : List (Nat × Nat)) (w : List Nat) (m : Nat)
    (hlen : w.length = n) (hwf : wellFormed n net = true) :
    ∀ k : Fin n, (getWire (evalNetBits w net) k.val).testBit m =
      applyNetBool net (fun idx : Fin n => (getWire w idx.val).testBit m) k := by
  induction net generalizing w with
  | nil => intro k; rfl
  | cons c rest ih =>
    rcases c with ⟨i, j⟩
    simp only [wellFormed, Bool.and_eq_true, decide_eq_true_eq] at hwf
    rcases hwf with ⟨⟨hij, hjn⟩, hwf_rest⟩
    have hin : i < n := Nat.lt_trans hij hjn
    intro k
    simp only [evalNetBits, applyNetBool, applyNet]
    let w' := setWire (setWire w i (getWire w i &&& getWire w j)) j (getWire w i ||| getWire w j)
    have hlen' : w'.length = n := by simp only [w', length_setWire, hlen]
    rw [ih w' hlen' hwf_rest k]
    apply applyNet_ext leBool rest
    intro idx
    simp only [w', applyComp, hij, hjn, and_self, dite_true]
    have hj_len : j < (setWire w i (getWire w i &&& getWire w j)).length := by rw [length_setWire, hlen]; exact hjn
    have hi_len : i < w.length := by rw [hlen]; exact hin
    rw [getWire_setWire _ j _ idx.val hj_len]
    by_cases hkj : idx.val = j
    · have hji : j ≠ i := by omega
      simp only [hkj, hji, ite_true, ite_false]; rw [Nat.testBit_or, cmpMax_leBool]
    · simp only [hkj, ite_false]; rw [getWire_setWire w i _ idx.val hi_len]
      by_cases hki : idx.val = i
      · simp only [hki, ite_true]; rw [Nat.testBit_and, cmpMin_leBool]
      · simp only [hki, ite_false]

/-- Count how many wires in `ws` have bit `m` set. -/
def listBitCount (m : Nat) : List Nat → Nat
  | [] => 0
  | w :: ws => (if w.testBit m then 1 else 0) + listBitCount m ws

theorem popStepAux_testBit (w m prev : Nat) (rest : List Nat) (k : Nat) :
    (getWire (popStepAux w prev rest) k).testBit m =
      ((getWire rest k).testBit m ||
        ((if k = 0 then prev else getWire rest (k - 1)).testBit m && w.testBit m)) := by
  induction rest generalizing prev k with
  | nil =>
    cases k with
    | zero => simp [popStepAux, getWire, Nat.testBit_and]
    | succ k => simp [popStepAux, getWire]
  | cons cur tail ih =>
    cases k with
    | zero => simp [popStepAux, getWire, Nat.testBit_or, Nat.testBit_and]
    | succ k =>
      simp only [popStepAux, getWire]
      rw [ih cur k]
      cases k with
      | zero => simp [getWire]
      | succ k => simp [getWire]

theorem popStep_testBit (w m : Nat) (dp : List Nat) (c : Nat)
    (hdp : ∀ k, (getWire dp k).testBit m = decide (k ≤ c)) :
    ∀ k, (getWire (popStep w dp) k).testBit m = decide (k ≤ c + (if w.testBit m then 1 else 0)) := by
  cases dp with
  | nil =>
    have h0 := hdp 0
    simp [getWire] at h0
  | cons d0 rest =>
    intro k
    cases k with
    | zero =>
      have h0 := hdp 0
      simpa [popStep, getWire] using h0
    | succ k =>
      simp only [popStep, getWire]
      rw [popStepAux_testBit w m d0 rest k]
      have hcur : (getWire rest k).testBit m = decide (k + 1 ≤ c) := hdp (k + 1)
      have hprev : (if k = 0 then d0 else getWire rest (k - 1)).testBit m = decide (k ≤ c) := by
        cases k with
        | zero => exact hdp 0
        | succ k => exact hdp (k + 1)
      rw [hcur, hprev]
      cases hw : w.testBit m
      · simp
      · simp only [Bool.and_true, ↓reduceIte]
        by_cases h1 : k + 1 ≤ c
        · have h1' : k ≤ c := by omega
          have h1'' : k + 1 ≤ c + 1 := by omega
          simp [h1, h1', h1'']
        · by_cases h2 : k ≤ c
          · have h2'' : k + 1 ≤ c + 1 := by omega
            simp [h1, h2, h2'']
          · have h2'' : ¬ (k + 1 ≤ c + 1) := by omega
            simp [h1, h2, h2'']

theorem popTableFold_testBit (ws dp : List Nat) (m c : Nat)
    (hdp : ∀ k, (getWire dp k).testBit m = decide (k ≤ c)) :
    ∀ k, (getWire (popTableFold ws dp) k).testBit m = decide (k ≤ c + listBitCount m ws) := by
  induction ws generalizing dp c with
  | nil =>
    intro k
    rw [popTableFold, listBitCount, Nat.add_zero]
    exact hdp k
  | cons w rest ih =>
    intro k
    simp only [popTableFold, listBitCount]
    have hstep := popStep_testBit w m dp c hdp
    rw [ih (popStep w dp) (c + (if w.testBit m then 1 else 0)) hstep k]
    have heq : c + (if w.testBit m then 1 else 0) + listBitCount m rest =
        c + ((if w.testBit m then 1 else 0) + listBitCount m rest) := by omega
    rw [heq]
    rfl

def encodeBitsAux {n : Nat} (v : Fin n → Bool) : (k : Nat) → k ≤ n → Nat
  | 0, _ => 0
  | k + 1, hk => encodeBitsAux v k (Nat.le_of_succ_le hk) ||| (if v ⟨k, hk⟩ then 2 ^ k else 0)

def encodeBits {n : Nat} (v : Fin n → Bool) : Nat :=
  encodeBitsAux v n (Nat.le_refl n)

theorem encodeBitsAux_lt {n : Nat} (v : Fin n → Bool) (k : Nat) (hk : k ≤ n) :
    encodeBitsAux v k hk < 2 ^ k := by
  induction k with
  | zero => simp [encodeBitsAux]
  | succ k ih =>
    simp only [encodeBitsAux]
    apply Nat.or_lt_two_pow
    · exact Nat.lt_trans (ih (Nat.le_of_succ_le hk)) (Nat.pow_lt_pow_right (by omega) (by omega))
    · split
      · exact Nat.pow_lt_pow_right (by omega) (by omega)
      · exact Nat.two_pow_pos (k + 1)

theorem encodeBitsAux_testBit {n : Nat} (v : Fin n → Bool) (k : Nat) (hk : k ≤ n) :
    ∀ i : Nat, (hi : i < k) →
      (encodeBitsAux v k hk).testBit i = v ⟨i, Nat.lt_of_lt_of_le hi hk⟩ := by
  induction k with
  | zero => intro _ hi; cases hi
  | succ k ih =>
    intro i hi
    simp only [encodeBitsAux, Nat.testBit_or]
    by_cases heq : i = k
    · subst heq
      have hzero := Nat.testBit_lt_two_pow (encodeBitsAux_lt v i (Nat.le_of_succ_le hk))
      rw [hzero, Bool.false_or]
      cases hv : v ⟨i, hk⟩ <;> simp
    · rw [ih (Nat.le_of_succ_le hk) i (by omega)]
      have hne : k ≠ i := by omega
      cases v ⟨k, hk⟩ <;> simp [hne]

theorem getWire_initWiresBits (n i : Nat) (hi : i < n) :
    getWire (initWiresBits n) i = wireMask n i := by
  rw [getWire_eq_getD, initWiresBits]
  simp [List.getD, hi]

theorem listBitCount_initWiresBits {n : Nat} (v : Fin n → Bool) :
    listBitCount (encodeBits v) (initWiresBits n) = countTrue n v := by
  let m := encodeBits v
  have hm : m < 2 ^ n := encodeBitsAux_lt v n (Nat.le_refl n)
  have hbit : ∀ i : Nat, (hi : i < n) → (wireMask n i).testBit m = v ⟨i, hi⟩ := by
    intro i hi
    rw [wireMask_testBit n i m hi hm]
    exact encodeBitsAux_testBit v n (Nat.le_refl n) i hi
  have aux : ∀ (k : Nat) (hk : k ≤ n),
      listBitCount m ((List.range k).map (wireMask n)) = countTrueAux v k hk := by
    intro k hk
    induction k with
    | zero => rfl
    | succ k ih =>
      rw [List.range_succ, List.map_append, List.map_cons, List.map_nil]
      have hadd : ∀ (xs ys : List Nat), listBitCount m (xs ++ ys) = listBitCount m xs + listBitCount m ys := by
        intro xs ys
        induction xs with
        | nil => simp [listBitCount]
        | cons x xs ihx => simp only [List.cons_append, listBitCount, ihx]; omega
      rw [hadd, ih (Nat.le_of_succ_le hk)]
      simp only [listBitCount, countTrueAux, hbit k hk, Nat.add_zero]
  exact aux n (Nat.le_refl n)

/-- **End-to-end soundness of `checkMedianNet`**: if `net` is well-formed on `n` wires with
`net.length = k` and `checkMedianNet n net = true`, then `ValidMedianNetwork n k`
(certifying median selection over every decidable linear order `(α, le)`). -/
theorem validMedianNetwork_of_check (n k : Nat) (net : List (Nat × Nat))
    (hwf : wellFormed n net = true) (hlen : net.length = k)
    (hchk : checkMedianNet n net = true) :
    ValidMedianNetwork n k := by
  refine ⟨net, hwf, hlen, zero_one_principle_median net ?_⟩
  intro v
  unfold IsBoolMedian
  by_cases hn0 : n = 0
  · simp [hn0]
  · simp only [hn0, ↓reduceDIte]
    unfold checkMedianNet at hchk
    have hn0_f : (n == 0) = false := beq_false_of_ne hn0
    simp only [hn0_f, Bool.false_eq_true, ↓reduceIte] at hchk
    let m := encodeBits v
    have hm : m < 2 ^ n := encodeBitsAux_lt v n (Nat.le_refl n)
    have hlen0 : (initWiresBits n).length = n := by simp [initWiresBits]
    have hinit : ∀ idx : Fin n, (getWire (initWiresBits n) idx.val).testBit m = v idx := by
      intro idx
      rw [getWire_initWiresBits n idx.val idx.isLt, wireMask_testBit n idx.val m idx.isLt hm]
      exact encodeBitsAux_testBit v n (Nat.le_refl n) idx.val idx.isLt
    have heval : ∀ wire : Fin n,
        (getWire (evalNetBits (initWiresBits n) net) wire.val).testBit m = applyNetBool net v wire := by
      intro wire
      rw [evalNetBits_testBit net (initWiresBits n) m hlen0 hwf wire]
      exact applyNet_ext leBool net hinit wire
    have hdp0 : ∀ r, (getWire [(1 <<< (1 <<< n)) - 1] r).testBit m = decide (r ≤ 0) := by
      intro r
      cases r with
      | zero =>
        simp only [getWire]
        have hp1 : (1 <<< n) = 2 ^ n := by rw [Nat.shiftLeft_eq, Nat.one_mul]
        have hp2 : (1 <<< (2 ^ n)) = 2 ^ (2 ^ n) := by rw [Nat.shiftLeft_eq, Nat.one_mul]
        rw [hp1, hp2, Nat.testBit_two_pow_sub_one]
        exact decide_eq_true hm
      | succ r => simp [getWire]
    have htbl : ∀ r, (getWire (popTableFold (initWiresBits n) [(1 <<< (1 <<< n)) - 1]) r).testBit m =
        decide (r ≤ countTrue n v) := by
      intro r
      rw [popTableFold_testBit (initWiresBits n) [(1 <<< (1 <<< n)) - 1] m 0 hdp0 r,
          Nat.zero_add, listBitCount_initWiresBits v]
    let mid := (n - 1) / 2
    by_cases hodd : n % 2 = 1
    · simp only [hodd, ↓reduceDIte]
      have hodd_t : (n % 2 == 1) = true := beq_iff_eq.2 hodd
      simp only [hodd_t, ↓reduceIte, beq_iff_eq] at hchk
      have htb := congrArg (fun x => x.testBit m) hchk
      rw [heval ⟨mid, by omega⟩, htbl (mid + 1)] at htb
      exact htb
    · simp only [hodd, ↓reduceDIte]
      have hodd_f : (n % 2 == 1) = false := beq_false_of_ne hodd
      simp only [hodd_f, Bool.false_eq_true, ↓reduceIte, Bool.and_eq_true, beq_iff_eq] at hchk
      rcases hchk with ⟨hlo, hhi⟩
      have htb1 := congrArg (fun x => x.testBit m) hlo
      have htb2 := congrArg (fun x => x.testBit m) hhi
      rw [Nat.testBit_and, heval ⟨mid, by omega⟩, heval ⟨mid + 1, by omega⟩, htbl (mid + 2)] at htb1
      rw [Nat.testBit_or, heval ⟨mid, by omega⟩, heval ⟨mid + 1, by omega⟩, htbl (mid + 1)] at htb2
      exact ⟨htb1, htb2⟩

end SelectNet
