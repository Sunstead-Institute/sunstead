/-!
# Optimal Sorting Networks: Semantics, Knuth's Zero-One Principle, and Kernel Evaluator

This module formalizes comparator networks on `n` wires in pure Lean 4.36.0 (zero Mathlib):

1. General linear-order semantics (`applyNet`, `IsSorted`) for any type `α` equipped with
   a reflexive, transitive, total comparator `le : α → α → Bool`.
2. A complete, sorry-free proof of **Knuth's Zero-One Principle** (`zero_one_principle`):
   a comparator network that sorts every Boolean vector `v : Fin n → Bool` sorts every
   input vector `v : Fin n → α` over every linear order `(α, le)`.
3. The mission predicate `ValidSortingNetwork n k` and its direct link
   `validSortingNetwork_sorts_all_linear_orders` to arbitrary linear orders.
4. A fast bit-sliced kernel evaluator (`checkSortNet n net : Bool`) evaluating all `2^n`
   Boolean inputs simultaneously as `2^n`-bit natural-number truth tables, together with its
   complete soundness theorem `checkSortNet_sound`.

Upstream benchmark records and open-problem targets are pinned to Bert Dobbelaere's
`bertdobbelaere/SorterHunter` at commit `3d8b3454bad15062f4b0030052f12d6550f8d89d` (MIT),
including `Networks/Sorters/Sort_10_29_8.json`, `Networks/Sorters/Sort_13_45_10.json`,
and `Networks/Sorters/Sort_16_60_10.json`.
-/

namespace SortNet

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

/-- Minimum of `a` and `b` under `le`. -/
def cmpMin {α : Type} (le : α → α → Bool) (a b : α) : α :=
  if le a b then a else b

/-- Maximum of `a` and `b` under `le`. -/
def cmpMax {α : Type} (le : α → α → Bool) (a b : α) : α :=
  if le a b then b else a

/-- Apply a single comparator `(i, j)` to wire state `v : Fin n → α`.
When `i < j ∧ j < n`, wire `i` receives `cmpMin le (v i) (v j)` and wire `j` receives
`cmpMax le (v i) (v j)`; out-of-range or inverted pairs leave `v` unchanged. -/
def applyComp {α : Type} {n : Nat} (le : α → α → Bool) (i j : Nat) (v : Fin n → α) : Fin n → α :=
  if h : i < j ∧ j < n then
    let a := v ⟨i, Nat.lt_trans h.1 h.2⟩
    let b := v ⟨j, h.2⟩
    fun k =>
      if k.val = i then cmpMin le a b
      else if k.val = j then cmpMax le a b
      else v k
  else v

/-- Sequentially apply a comparator network `net` to wire state `v : Fin n → α`. -/
def applyNet {α : Type} {n : Nat} (le : α → α → Bool) :
    List (Nat × Nat) → (Fin n → α) → (Fin n → α)
  | [], v => v
  | (i, j) :: rest, v => applyNet le rest (applyComp le i j v)

/-- Wire state `v : Fin n → α` is sorted in non-decreasing order under `le`. -/
def IsSorted {α : Type} {n : Nat} (le : α → α → Bool) (v : Fin n → α) : Prop :=
  ∀ i j : Fin n, i.val ≤ j.val → le (v i) (v j) = true

/-- Standard Boolean linear order (`false ≤ false`, `false ≤ true`, `true ≤ true`). -/
def leBool (a b : Bool) : Bool := !a || b

/-- Apply a comparator network to a Boolean input vector `v : Fin n → Bool`. -/
def applyNetBool {n : Nat} (net : List (Nat × Nat)) (v : Fin n → Bool) : Fin n → Bool :=
  applyNet leBool net v

/-- A Boolean wire vector `v : Fin n → Bool` is sorted (`false` before `true`). -/
def IsSortedBool {n : Nat} (v : Fin n → Bool) : Prop :=
  IsSorted leBool v

theorem cmpMin_leBool (a b : Bool) : cmpMin leBool a b = (a && b) := by
  cases a <;> cases b <;> rfl

theorem cmpMax_leBool (a b : Bool) : cmpMax leBool a b = (a || b) := by
  cases a <;> cases b <;> rfl

/-! ## Knuth's Zero-One Principle -/

/-- Monotone threshold map sending `x ↦ true` iff `¬(x ≤ t)`. -/
def thresh {α : Type} (le : α → α → Bool) (t x : α) : Bool :=
  !(le x t)

theorem thresh_cmpMin {α : Type} (le : α → α → Bool) (hlo : IsLinearOrder le) (t a b : α) :
    thresh le t (cmpMin le a b) = cmpMin leBool (thresh le t a) (thresh le t b) := by
  unfold thresh cmpMin
  cases hab : le a b
  · have hba : le b a = true := by
      rcases hlo.total a b with h | h
      · rw [hab] at h; cases h
      · exact h
    cases hat : le a t <;> cases hbt : le b t
    · simp [hbt, leBool]
    · simp [hbt, leBool]
    · have := hlo.trans b a t hba hat; rw [hbt] at this; cases this
    · simp [hbt, leBool]
  · cases hat : le a t <;> cases hbt : le b t
    · simp [hat, leBool]
    · have := hlo.trans a b t hab hbt; rw [hat] at this; cases this
    · simp [hat, leBool]
    · simp [hat, leBool]

theorem thresh_cmpMax {α : Type} (le : α → α → Bool) (hlo : IsLinearOrder le) (t a b : α) :
    thresh le t (cmpMax le a b) = cmpMax leBool (thresh le t a) (thresh le t b) := by
  unfold thresh cmpMax
  cases hab : le a b
  · have hba : le b a = true := by
      rcases hlo.total a b with h | h
      · rw [hab] at h; cases h
      · exact h
    cases hat : le a t <;> cases hbt : le b t
    · simp [hat, leBool]
    · simp [hat, leBool]
    · have := hlo.trans b a t hba hat; rw [hbt] at this; cases this
    · simp [hat, leBool]
  · cases hat : le a t <;> cases hbt : le b t
    · simp [hbt, leBool]
    · have := hlo.trans a b t hab hbt; rw [hat] at this; cases this
    · simp [hbt, leBool]
    · simp [hbt, leBool]

theorem applyComp_ext {α : Type} {n : Nat} (le : α → α → Bool) (i j : Nat)
    {v₁ v₂ : Fin n → α} (h : ∀ k, v₁ k = v₂ k) :
    ∀ k, applyComp le i j v₁ k = applyComp le i j v₂ k := by
  intro k
  unfold applyComp
  split
  · simp only [h]
  · exact h k

theorem applyNet_ext {α : Type} {n : Nat} (le : α → α → Bool) (net : List (Nat × Nat))
    {v₁ v₂ : Fin n → α} (h : ∀ k, v₁ k = v₂ k) :
    ∀ k, applyNet le net v₁ k = applyNet le net v₂ k := by
  induction net generalizing v₁ v₂ with
  | nil => exact h
  | cons c rest ih =>
    rcases c with ⟨i, j⟩
    exact ih (applyComp_ext le i j h)

theorem thresh_applyComp {α : Type} {n : Nat} (le : α → α → Bool) (hlo : IsLinearOrder le)
    (t : α) (i j : Nat) (v : Fin n → α) (k : Fin n) :
    thresh le t (applyComp le i j v k) =
      applyComp leBool i j (fun idx => thresh le t (v idx)) k := by
  unfold applyComp
  split
  · dsimp only
    split
    · exact thresh_cmpMin le hlo t _ _
    · split
      · exact thresh_cmpMax le hlo t _ _
      · rfl
  · rfl

theorem thresh_applyNet {α : Type} {n : Nat} (le : α → α → Bool) (hlo : IsLinearOrder le)
    (t : α) (net : List (Nat × Nat)) (v : Fin n → α) :
    ∀ k, thresh le t (applyNet le net v k) =
      applyNetBool net (fun idx => thresh le t (v idx)) k := by
  induction net generalizing v with
  | nil => intro k; rfl
  | cons c rest ih =>
    rcases c with ⟨i, j⟩
    intro k
    simp only [applyNet, applyNetBool]
    rw [ih (applyComp le i j v) k]
    exact applyNet_ext leBool rest (thresh_applyComp le hlo t i j v) k

/-- **Knuth's Zero-One Principle**: if a comparator network sorts all `2^n` Boolean vectors,
then it sorts all input vectors over every decidable linear order `(α, le)`. -/
theorem zero_one_principle {n : Nat} (net : List (Nat × Nat))
    (hbool : ∀ v : Fin n → Bool, IsSortedBool (applyNetBool net v)) :
    ∀ {α : Type} (le : α → α → Bool), IsLinearOrder le →
      ∀ v : Fin n → α, IsSorted le (applyNet le net v) := by
  intro α le hlo v i j hij
  cases h : le (applyNet le net v i) (applyNet le net v j)
  · have hsorted := hbool (fun idx => thresh le (applyNet le net v j) (v idx)) i j hij
    have hi : applyNetBool net (fun idx => thresh le (applyNet le net v j) (v idx)) i = true := by
      rw [← thresh_applyNet le hlo (applyNet le net v j) net v i]
      simp [thresh, h]
    have hj : applyNetBool net (fun idx => thresh le (applyNet le net v j) (v idx)) j = false := by
      rw [← thresh_applyNet le hlo (applyNet le net v j) net v j]
      simp [thresh, hlo.refl]
    rw [hi, hj] at hsorted
    cases hsorted
  · rfl

/-! ## Mission target predicate -/

/-- Existence of a well-formed sorting network on `n` wires with exactly `k` comparators. -/
def ValidSortingNetwork (n k : Nat) : Prop :=
  ∃ net : List (Nat × Nat),
    wellFormed n net = true ∧
    net.length = k ∧
    ∀ v : Fin n → Bool, IsSortedBool (applyNetBool net v)

/-- Every `ValidSortingNetwork n k` witnesses a `k`-comparator network that sorts every
input vector over every decidable linear order `(α, le)`. -/
theorem validSortingNetwork_sorts_all_linear_orders {n k : Nat}
    (h : ValidSortingNetwork n k) :
    ∃ net : List (Nat × Nat),
      wellFormed n net = true ∧
      net.length = k ∧
      ∀ {α : Type} (le : α → α → Bool), IsLinearOrder le →
        ∀ v : Fin n → α, IsSorted le (applyNet le net v) := by
  rcases h with ⟨net, hwf, hlen, hbool⟩
  exact ⟨net, hwf, hlen, zero_one_principle net hbool⟩

/-! ## Fast bit-sliced kernel evaluator and soundness proof -/

/-- Repeat the low `step`-bit pattern `2^k` times across `step * 2^k` bits. -/
def repMask : Nat → Nat → Nat → Nat
  | 0, _, x => x
  | k + 1, step, x => repMask k (step * 2) (x ||| (x <<< step))

/-- `2^n`-bit truth table of wire `b` (`b < n`): bit `m` equals `m.testBit b` for all `m < 2^n`. -/
def wireMask (n b : Nat) : Nat :=
  let half := 1 <<< b
  let block := ((1 <<< half) - 1) <<< half
  repMask (n - b - 1) (2 * half) block

/-- Initial bit-sliced wire table for `n` wires covering all `2^n` Boolean inputs in parallel. -/
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

/-- Apply a comparator network in parallel across all `2^n` inputs via bitwise AND/OR. -/
def evalNetBits (w : List Nat) : List (Nat × Nat) → List Nat
  | [] => w
  | (i, j) :: rest =>
    let a := getWire w i
    let b := getWire w j
    evalNetBits (setWire (setWire w i (a &&& b)) j (a ||| b)) rest

/-- Check that every adjacent wire pair satisfies `w_i ≤ w_{i+1}` at every bit position
(`w_i ||| w_{i+1} == w_{i+1}`, i.e., never `1` before `0`). -/
def sortedWires : List Nat → Bool
  | [] => true
  | [_] => true
  | a :: b :: rest => ((a ||| b) == b) && sortedWires (b :: rest)

/-- Kernel-decidable bit-sliced verifier testing all `2^n` Boolean inputs in a single pass. -/
def checkSortNet (n : Nat) (net : List (Nat × Nat)) : Bool :=
  sortedWires (evalNetBits (initWiresBits n) net)

/-! ### Bit-table soundness lemmas -/

theorem repMask_testBit (k step x : Nat) (hstep : 0 < step)
    (hhi : ∀ r, step ≤ r → x.testBit r = false) :
    (∀ m, m < step * 2 ^ k → (repMask k step x).testBit m = x.testBit (m % step)) ∧
    (∀ m, step * 2 ^ k ≤ m → (repMask k step x).testBit m = false) := by
  induction k generalizing step x with
  | zero =>
    constructor
    · intro m hm
      simp only [Nat.pow_zero, Nat.mul_one] at hm
      simp [repMask, Nat.mod_eq_of_lt hm]
    · intro m hm
      simp only [Nat.pow_zero, Nat.mul_one] at hm
      exact hhi m hm
  | succ k ih =>
    have hstep2 : 0 < step * 2 := by omega
    have hhi' : ∀ r, step * 2 ≤ r → (x ||| (x <<< step)).testBit r = false := by
      intro r hr
      rw [Nat.testBit_or, Nat.testBit_shiftLeft]
      have h1 : x.testBit r = false := hhi r (by omega)
      have h2 : x.testBit (r - step) = false := hhi (r - step) (by omega)
      simp [h1, h2]
    have hpow : step * 2 * 2 ^ k = step * 2 ^ (k + 1) := by
      rw [Nat.pow_succ, Nat.mul_assoc]
      have : 2 * 2 ^ k = 2 ^ k * 2 := Nat.mul_comm 2 (2 ^ k)
      rw [this]
    rcases ih (step * 2) (x ||| (x <<< step)) hstep2 hhi' with ⟨hlo, hge⟩
    constructor
    · intro m hm
      rw [repMask, hlo m (by rw [hpow]; exact hm)]
      let r := m % (step * 2)
      have hrlt : r < step * 2 := Nat.mod_lt m hstep2
      have hmod : r % step = m % step := by
        have hdvd : step ∣ step * 2 := Nat.dvd_mul_right step 2
        exact Nat.mod_mod_of_dvd m hdvd
      rw [Nat.testBit_or, Nat.testBit_shiftLeft]
      by_cases hlt : r < step
      · have hge_f : decide (r ≥ step) = false := decide_eq_false (by omega)
        rw [hge_f]
        simp only [Bool.false_and, Bool.or_false]
        rw [← hmod, Nat.mod_eq_of_lt hlt]
      · have hge_t : decide (r ≥ step) = true := decide_eq_true (by omega)
        have hxr : x.testBit r = false := hhi r (by omega)
        rw [hxr, hge_t]
        simp only [Bool.false_or, Bool.true_and]
        have hsub : r - step = r % step := by
          have hlt2 : r - step < step := by omega
          have hr_eq : r = (r - step) + step := by omega
          have hmod_r : r % step = ((r - step) + step) % step := congrArg (· % step) hr_eq
          rw [Nat.add_mod_right, Nat.mod_eq_of_lt hlt2] at hmod_r
          exact hmod_r.symm
        rw [hsub, hmod]
    · intro m hm
      rw [repMask]
      exact hge m (by rw [hpow]; exact hm)

theorem wireMask_testBit (n b m : Nat) (hb : b < n) (hm : m < 2 ^ n) :
    (wireMask n b).testBit m = m.testBit b := by
  unfold wireMask
  have hhalf_eq : (1 <<< b) = 2 ^ b := by
    rw [Nat.shiftLeft_eq, Nat.one_mul]
  have h2half_eq : 2 * (1 <<< b) = 2 ^ (b + 1) := by
    rw [hhalf_eq, Nat.pow_succ, Nat.mul_comm]
  have hpow_mul : 2 * (1 <<< b) * 2 ^ (n - b - 1) = 2 ^ n := by
    rw [h2half_eq, ← Nat.pow_add]
    congr 1
    omega
  have hstep_pos : 0 < 2 * (1 <<< b) := by
    rw [h2half_eq]
    exact Nat.two_pow_pos (b + 1)
  have hblock_hi : ∀ r, 2 * (1 <<< b) ≤ r →
      (((1 <<< (1 <<< b)) - 1) <<< (1 <<< b)).testBit r = false := by
    intro r hr
    rw [Nat.testBit_shiftLeft]
    simp only [Nat.shiftLeft_eq, Nat.one_mul, Nat.testBit_two_pow_sub_one]
    rw [hhalf_eq] at hr
    have hlt : ¬ (r - 2 ^ b < 2 ^ b) := by omega
    simp [hlt]
  have hrep := (repMask_testBit (n - b - 1) (2 * (1 <<< b))
    (((1 <<< (1 <<< b)) - 1) <<< (1 <<< b)) hstep_pos hblock_hi).1 m (by rw [hpow_mul]; exact hm)
  rw [hrep, Nat.testBit_shiftLeft]
  simp only [Nat.shiftLeft_eq, Nat.one_mul, Nat.testBit_two_pow_sub_one]
  let r := m % (2 * 2 ^ b)
  have hrlt : r < 2 * 2 ^ b := by
    show m % (2 * 2 ^ b) < 2 * 2 ^ b
    rw [← hhalf_eq]
    exact Nat.mod_lt m hstep_pos
  have hmod_tb : r.testBit b = m.testBit b := by
    show (m % (2 * 2 ^ b)).testBit b = m.testBit b
    rw [← hhalf_eq, h2half_eq, Nat.testBit_mod_two_pow]
    simp
  rw [← hmod_tb]
  change (decide (r ≥ 2 ^ b) && decide (r - 2 ^ b < 2 ^ b)) = r.testBit b
  rw [Nat.testBit_eq_decide_div_mod_eq]
  by_cases hlt : r < 2 ^ b
  · have h1 : decide (r ≥ 2 ^ b) = false := decide_eq_false (by omega)
    have hdiv : r / 2 ^ b = 0 := Nat.div_eq_of_lt hlt
    simp [h1, hdiv]
  · have h1 : decide (r ≥ 2 ^ b) = true := decide_eq_true (by omega)
    have h2 : decide (r - 2 ^ b < 2 ^ b) = true := decide_eq_true (by omega)
    have hdiv : r / 2 ^ b = 1 := by
      have hge : 1 * 2 ^ b ≤ r := by omega
      have hlt2 : r < 2 * 2 ^ b := by omega
      have hpos : 0 < 2 ^ b := Nat.two_pow_pos b
      have hlo : 1 ≤ r / 2 ^ b := (Nat.le_div_iff_mul_le hpos).2 hge
      have hhi : r / 2 ^ b < 2 := (Nat.div_lt_iff_lt_mul hpos).2 hlt2
      omega
    simp [h1, h2, hdiv]

theorem getWire_eq_getD (w : List Nat) (i : Nat) : getWire w i = w.getD i 0 := by
  induction w generalizing i with
  | nil => simp [getWire]
  | cons x xs ih =>
    cases i with
    | zero => rfl
    | succ i => exact ih i

theorem length_setWire (w : List Nat) (i v : Nat) : (setWire w i v).length = w.length := by
  induction w generalizing i with
  | nil => rfl
  | cons x xs ih =>
    cases i with
    | zero => rfl
    | succ i => simp [setWire, ih]

theorem getWire_setWire (w : List Nat) (i v k : Nat) (hi : i < w.length) :
    getWire (setWire w i v) k = if k = i then v else getWire w k := by
  induction w generalizing i k with
  | nil => cases hi
  | cons x xs ih =>
    cases i with
    | zero =>
      cases k with
      | zero => rfl
      | succ k => simp [setWire, getWire]
    | succ i =>
      cases k with
      | zero => simp [setWire, getWire]
      | succ k =>
        simp only [setWire, getWire]
        rw [ih i k (Nat.lt_of_succ_lt_succ hi)]
        by_cases hki : k = i
        · subst hki; simp
        · simp [hki]

theorem length_evalNetBits (w : List Nat) (net : List (Nat × Nat)) :
    (evalNetBits w net).length = w.length := by
  induction net generalizing w with
  | nil => rfl
  | cons c rest ih =>
    rcases c with ⟨i, j⟩
    simp only [evalNetBits]
    rw [ih, length_setWire, length_setWire]

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
    have hlen' : w'.length = n := by
      simp only [w', length_setWire, hlen]
    rw [ih w' hlen' hwf_rest k]
    apply applyNet_ext leBool rest
    intro idx
    simp only [w', applyComp, hij, hjn, and_self, dite_true]
    have hj_len : j < (setWire w i (getWire w i &&& getWire w j)).length := by
      rw [length_setWire, hlen]; exact hjn
    have hi_len : i < w.length := by rw [hlen]; exact hin
    rw [getWire_setWire _ j _ idx.val hj_len]
    by_cases hkj : idx.val = j
    · have hji : j ≠ i := by omega
      simp only [hkj, hji, ite_true, ite_false]
      rw [Nat.testBit_or, cmpMax_leBool]
    · simp only [hkj, ite_false]
      rw [getWire_setWire w i _ idx.val hi_len]
      by_cases hki : idx.val = i
      · simp only [hki, ite_true]
        rw [Nat.testBit_and, cmpMin_leBool]
      · simp only [hki, ite_false]

theorem sortedWires_adj (w : List Nat) (h : sortedWires w = true) :
    ∀ i : Nat, i + 1 < w.length →
      ((getWire w i) ||| (getWire w (i + 1))) = getWire w (i + 1) := by
  induction w with
  | nil => intro i hi; cases hi
  | cons a rest ih =>
    cases rest with
    | nil => intro i hi; simp at hi
    | cons b tail =>
      simp only [sortedWires, Bool.and_eq_true, beq_iff_eq] at h
      intro i hi
      cases i with
      | zero => exact h.1
      | succ i =>
        exact ih h.2 i (Nat.lt_of_succ_lt_succ hi)

theorem isSortedBool_of_adj {n : Nat} (v : Fin n → Bool)
    (hadj : ∀ i : Nat, (h : i + 1 < n) → leBool (v ⟨i, Nat.lt_of_succ_lt h⟩) (v ⟨i + 1, h⟩) = true) :
    IsSortedBool v := by
  intro i j hij
  obtain ⟨d, hd⟩ := Nat.exists_eq_add_of_le hij
  induction d generalizing i with
  | zero =>
    have heq : i = j := Fin.ext (by omega)
    subst heq
    cases v i <;> rfl
  | succ d ih =>
    have hlt : i.val + 1 < n := by omega
    have hstep : leBool (v i) (v ⟨i.val + 1, hlt⟩) = true := hadj i.val hlt
    have hrest : leBool (v ⟨i.val + 1, hlt⟩) (v j) = true :=
      ih ⟨i.val + 1, hlt⟩ (by dsimp only; omega) (by dsimp only; omega)
    cases h1 : v i <;> cases h2 : v ⟨i.val + 1, hlt⟩ <;> cases h3 : v j
    · rfl
    · rfl
    · rfl
    · rfl
    · simp only [leBool, h1, h2] at hstep; cases hstep
    · simp only [leBool, h1, h2] at hstep; cases hstep
    · simp only [leBool, h2, h3] at hrest; cases hrest
    · rfl

def encodeBitsAux {n : Nat} (v : Fin n → Bool) : (k : Nat) → k ≤ n → Nat
  | 0, _ => 0
  | k + 1, hk =>
    encodeBitsAux v k (Nat.le_of_succ_le hk) |||
      (if v ⟨k, hk⟩ then 2 ^ k else 0)

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
  | zero => intro i hi; cases hi
  | succ k ih =>
    intro i hi
    simp only [encodeBitsAux, Nat.testBit_or]
    by_cases heq : i = k
    · subst heq
      have hlt : encodeBitsAux v i (Nat.le_of_succ_le hk) < 2 ^ i :=
        encodeBitsAux_lt v i (Nat.le_of_succ_le hk)
      have hzero : (encodeBitsAux v i (Nat.le_of_succ_le hk)).testBit i = false :=
        Nat.testBit_lt_two_pow hlt
      rw [hzero, Bool.false_or]
      cases hv : v ⟨i, hk⟩ <;> simp
    · have hlt : i < k := by omega
      rw [ih (Nat.le_of_succ_le hk) i hlt]
      have hne : k ≠ i := by omega
      cases hv : v ⟨k, hk⟩
      · simp
      · simp [hne]

theorem getWire_initWiresBits (n i : Nat) (hi : i < n) :
    getWire (initWiresBits n) i = wireMask n i := by
  rw [getWire_eq_getD, initWiresBits]
  simp [List.getD, hi]

/-- **Soundness of `checkSortNet`**: if `net` is well-formed on `n` wires and passes the
bit-sliced kernel check `checkSortNet n net = true`, then `net` sorts every Boolean input
`v : Fin n → Bool`. Combined with `zero_one_principle`, it sorts every linear order. -/
theorem checkSortNet_sound (n : Nat) (net : List (Nat × Nat))
    (hwf : wellFormed n net = true) (hchk : checkSortNet n net = true) :
    ∀ v : Fin n → Bool, IsSortedBool (applyNetBool net v) := by
  intro v
  let m := encodeBits v
  have hm : m < 2 ^ n := encodeBitsAux_lt v n (Nat.le_refl n)
  have hlen0 : (initWiresBits n).length = n := by simp [initWiresBits]
  have hlenF : (evalNetBits (initWiresBits n) net).length = n := by
    rw [length_evalNetBits, hlen0]
  have hinit : ∀ idx : Fin n, (getWire (initWiresBits n) idx.val).testBit m = v idx := by
    intro idx
    rw [getWire_initWiresBits n idx.val idx.isLt, wireMask_testBit n idx.val m idx.isLt hm]
    exact encodeBitsAux_testBit v n (Nat.le_refl n) idx.val idx.isLt
  have heval : ∀ k : Fin n,
      (getWire (evalNetBits (initWiresBits n) net) k.val).testBit m = applyNetBool net v k := by
    intro k
    rw [evalNetBits_testBit net (initWiresBits n) m hlen0 hwf k]
    exact applyNet_ext leBool net hinit k
  apply isSortedBool_of_adj
  intro i hi
  have hadj := sortedWires_adj (evalNetBits (initWiresBits n) net) hchk i (by rw [hlenF]; exact hi)
  have htb : ((getWire (evalNetBits (initWiresBits n) net) i) |||
      (getWire (evalNetBits (initWiresBits n) net) (i + 1))).testBit m =
      (getWire (evalNetBits (initWiresBits n) net) (i + 1)).testBit m :=
    congrArg (fun x => x.testBit m) hadj
  rw [Nat.testBit_or, heval ⟨i, Nat.lt_of_succ_lt hi⟩, heval ⟨i + 1, hi⟩] at htb
  cases h1 : applyNetBool net v ⟨i, Nat.lt_of_succ_lt hi⟩ <;>
    cases h2 : applyNetBool net v ⟨i + 1, hi⟩
  · rfl
  · rfl
  · rw [h1, h2] at htb; cases htb
  · rfl

end SortNet
