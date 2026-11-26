/-!
# Optimal-Depth Sorting Networks: Parallel Semantics, Wire Disjointness, Knuth's Zero-One Principle, and Kernel Evaluator

This module formalizes parallel-layered comparator sorting networks on `n` wires in pure
Lean 4.36.0 (zero Mathlib):

1. General linear-order semantics (`applyComp`, `applyNet`, `applyLayer`, `applyLayers`,
   `IsSorted`) for any type `α` equipped with a reflexive, transitive, total comparator
   `le : α → α → Bool`.
2. Formal wire-disjointness and simultaneous 1-clock-cycle parallel layer semantics:
   - `layerDisjoint_sound` and `wellFormedLayers_sound` prove that the kernel-decidable
     check `wellFormedLayers n layers = true` enforces `i < j < n` and pairwise disjoint
     wires (`LayerDisjointProp`) in every layer.
   - `applyComp_comm` proves that disjoint comparators commute on all inputs.
   - `applyLayer_parallel_spec` proves that evaluating a well-formed layer computes the
     exact simultaneous 1-clock-cycle parallel compare-exchange update from the pre-layer
     wire state.
3. A complete, sorry-free proof of **Knuth's Zero-One Principle** (`zero_one_principle`,
   `zero_one_principle_layers`): a layered comparator network that sorts every Boolean
   vector `v : Fin n → Bool` sorts every vector `v : Fin n → α` over every decidable
   linear order `(α, le)` (and in particular every `v : Fin n → Nat`).
4. The mission target predicate `ValidParallelSortingNetwork n d` and a fast bit-sliced
   kernel evaluator (`checkSortLayers n layers : Bool`) testing all `2^n` Boolean inputs
   simultaneously as `2^n`-bit natural-number truth tables, together with its complete
   soundness theorem `checkSortLayers_sound` and `validParallelSortingNetwork_of_check`.

Upstream depth benchmarks and `computeDepth` reference are pinned to Bert Dobbelaere's
`bertdobbelaere/SorterHunter` at commit `3d8b3454bad15062f4b0030052f12d6550f8d89d` (MIT),
including `SorterHunter.cpp`, `Networks/Sorters/Sort_10_31_7.json`,
`Networks/Sorters/Sort_12_40_8.json`, and `Networks/Sorters/Sort_16_61_9.json`.
-/

namespace SortDepth

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

/-- Sequentially apply a comparator list `net` to wire state `v : Fin n → α`. -/
def applyNet {α : Type} {n : Nat} (le : α → α → Bool) :
    List (Nat × Nat) → (Fin n → α) → (Fin n → α)
  | [], v => v
  | (i, j) :: rest, v => applyNet le rest (applyComp le i j v)

/-- Wire state `v : Fin n → α` is sorted in non-decreasing order under `le`. -/
def IsSorted {α : Type} {n : Nat} (le : α → α → Bool) (v : Fin n → α) : Prop :=
  ∀ i j : Fin n, i.val ≤ j.val → le (v i) (v j) = true

/-- Standard Boolean linear order (`false ≤ false`, `false ≤ true`, `true ≤ true`). -/
def leBool (a b : Bool) : Bool := !a || b

/-- Apply a comparator list to a Boolean input vector `v : Fin n → Bool`. -/
def applyNetBool {n : Nat} (net : List (Nat × Nat)) (v : Fin n → Bool) : Fin n → Bool :=
  applyNet leBool net v

/-- A Boolean wire vector `v : Fin n → Bool` is sorted (`false` before `true`). -/
def IsSortedBool {n : Nat} (v : Fin n → Bool) : Prop :=
  IsSorted leBool v

theorem cmpMin_leBool (a b : Bool) : cmpMin leBool a b = (a && b) := by
  cases a <;> cases b <;> rfl

theorem cmpMax_leBool (a b : Bool) : cmpMax leBool a b = (a || b) := by
  cases a <;> cases b <;> rfl

/-! ## Parallel layers, wire disjointness, and simultaneous execution semantics -/

/-- All wire endpoints touched by a layer: comparator `(i, j)` contributes `[i, j]`. -/
def layerWires : List (Nat × Nat) → List Nat
  | [] => []
  | (i, j) :: rest => i :: j :: layerWires rest

/-- Check whether wire index `x` occurs in `xs`. -/
def memNat (x : Nat) : List Nat → Bool
  | [] => false
  | y :: ys => (x == y) || memNat x ys

/-- Check that all wire indices in `xs` are pairwise distinct. -/
def distinctNats : List Nat → Bool
  | [] => true
  | x :: xs => !(memNat x xs) && distinctNats xs

/-- Boolean check that all comparators in `layer` act on pairwise disjoint wires. -/
def layerDisjoint (layer : List (Nat × Nat)) : Bool :=
  distinctNats (layerWires layer)

/-- Check that a single parallel layer on `n` wires has valid ordered comparators
`i < j < n` and pairwise disjoint wires (executable in 1 parallel clock cycle). -/
def wellFormedLayer (n : Nat) (layer : List (Nat × Nat)) : Bool :=
  wellFormed n layer && layerDisjoint layer

/-- Check that every layer in a parallel sorting network on `n` wires is well-formed. -/
def wellFormedLayers (n : Nat) : List (List (Nat × Nat)) → Bool
  | [] => true
  | layer :: rest => wellFormedLayer n layer && wellFormedLayers n rest

/-- Two comparators `(i₁, j₁)` and `(i₂, j₂)` share no wire index. -/
def CompsDisjoint (c₁ c₂ : Nat × Nat) : Prop :=
  c₁.1 ≠ c₂.1 ∧ c₁.1 ≠ c₂.2 ∧ c₁.2 ≠ c₂.1 ∧ c₁.2 ≠ c₂.2

/-- Prop-level pairwise wire disjointness for a parallel layer: every comparator connects
two distinct wires, and any two distinct comparators in the layer act on disjoint wires. -/
def LayerDisjointProp (layer : List (Nat × Nat)) : Prop :=
  (∀ c ∈ layer, c.1 ≠ c.2) ∧ List.Pairwise CompsDisjoint layer

/-- Prop-level well-formedness of a single parallel layer on `n` wires. -/
def WellFormedLayer (n : Nat) (layer : List (Nat × Nat)) : Prop :=
  (∀ c ∈ layer, c.1 < c.2 ∧ c.2 < n) ∧ LayerDisjointProp layer

/-- Prop-level well-formedness of a sequence of parallel layers on `n` wires. -/
def WellFormedLayers (n : Nat) (layers : List (List (Nat × Nat))) : Prop :=
  ∀ layer ∈ layers, WellFormedLayer n layer

/-- Apply a single parallel layer to wire state `v : Fin n → α`.
When `WellFormedLayer n layer` holds, all comparators in `layer` touch pairwise disjoint
wires, so execution is order-independent (`applyComp_comm`) and identical to simultaneous
1-clock-cycle parallel evaluation (`applyLayer_parallel_spec`). -/
def applyLayer {α : Type} {n : Nat} (le : α → α → Bool)
    (layer : List (Nat × Nat)) (v : Fin n → α) : Fin n → α :=
  applyNet le layer v

/-- Apply a sequence of parallel comparator layers to wire state `v : Fin n → α`. -/
def applyLayers {α : Type} {n : Nat} (le : α → α → Bool) :
    List (List (Nat × Nat)) → (Fin n → α) → (Fin n → α)
  | [], v => v
  | layer :: rest, v => applyLayers le rest (applyLayer le layer v)

/-- Apply a single parallel layer to a Boolean input vector. -/
def applyLayerBool {n : Nat} (layer : List (Nat × Nat)) (v : Fin n → Bool) : Fin n → Bool :=
  applyLayer leBool layer v

/-- Apply a sequence of parallel layers to a Boolean input vector. -/
def applyLayersBool {n : Nat} (layers : List (List (Nat × Nat))) (v : Fin n → Bool) :
    Fin n → Bool :=
  applyLayers leBool layers v

/-- Flatten a layered parallel network into its underlying comparator sequence. -/
def flattenLayers : List (List (Nat × Nat)) → List (Nat × Nat)
  | [] => []
  | layer :: rest => layer ++ flattenLayers rest

theorem memNat_eq_false (x : Nat) (xs : List Nat) (h : memNat x xs = false) :
    ∀ y ∈ xs, x ≠ y := by
  induction xs with
  | nil => intro y hy; cases hy
  | cons z zs ih =>
    simp only [memNat, Bool.or_eq_false_iff, beq_eq_false_iff_ne] at h
    intro y hy
    rcases List.mem_cons.1 hy with rfl | hyz
    · exact h.1
    · exact ih h.2 y hyz

theorem distinctNats_sound (xs : List Nat) (h : distinctNats xs = true) :
    List.Pairwise (· ≠ ·) xs := by
  induction xs with
  | nil => exact List.Pairwise.nil
  | cons x xs ih =>
    simp only [distinctNats, Bool.and_eq_true, Bool.not_eq_true'] at h
    exact List.Pairwise.cons (memNat_eq_false x xs h.1) (ih h.2)

theorem mem_layerWires_of_mem {layer : List (Nat × Nat)} {c : Nat × Nat} (hc : c ∈ layer) :
    c.1 ∈ layerWires layer ∧ c.2 ∈ layerWires layer := by
  induction layer with
  | nil => cases hc
  | cons p rest ih =>
    rcases p with ⟨i, j⟩
    rcases List.mem_cons.1 hc with rfl | hrest
    · simp [layerWires]
    · rcases ih hrest with ⟨h1, h2⟩
      exact ⟨List.mem_cons_of_mem _ (List.mem_cons_of_mem _ h1),
             List.mem_cons_of_mem _ (List.mem_cons_of_mem _ h2)⟩

theorem layerDisjoint_of_pairwise {layer : List (Nat × Nat)}
    (h : List.Pairwise (· ≠ ·) (layerWires layer)) :
    LayerDisjointProp layer := by
  induction layer with
  | nil => exact ⟨(fun _ hc => nomatch hc), List.Pairwise.nil⟩
  | cons p rest ih =>
    rcases p with ⟨i, j⟩
    simp only [layerWires] at h
    rcases List.pairwise_cons.1 h with ⟨hi, hjrest⟩
    rcases List.pairwise_cons.1 hjrest with ⟨hj, hrest⟩
    rcases ih hrest with ⟨hneq_rest, hpw_rest⟩
    have hij : i ≠ j := hi j (by simp)
    have hdisj : ∀ c ∈ rest, CompsDisjoint (i, j) c := by
      intro c hc
      rcases mem_layerWires_of_mem hc with ⟨hc1, hc2⟩
      exact ⟨hi c.1 (List.mem_cons_of_mem _ hc1),
             hi c.2 (List.mem_cons_of_mem _ hc2),
             hj c.1 hc1,
             hj c.2 hc2⟩
    constructor
    · intro c hc
      rcases List.mem_cons.1 hc with rfl | hc'
      · exact hij
      · exact hneq_rest c hc'
    · exact List.Pairwise.cons hdisj hpw_rest

/-- **Soundness of `layerDisjoint`**: if `layerDisjoint layer = true`, no wire index appears
more than once across all comparators in `layer`. -/
theorem layerDisjoint_sound (layer : List (Nat × Nat)) (h : layerDisjoint layer = true) :
    LayerDisjointProp layer :=
  layerDisjoint_of_pairwise (distinctNats_sound (layerWires layer) h)

theorem wellFormed_sound (n : Nat) (net : List (Nat × Nat)) (h : wellFormed n net = true) :
    ∀ c ∈ net, c.1 < c.2 ∧ c.2 < n := by
  induction net with
  | nil => intro c hc; cases hc
  | cons p rest ih =>
    rcases p with ⟨i, j⟩
    simp only [wellFormed, Bool.and_eq_true, decide_eq_true_eq] at h
    intro c hc
    rcases List.mem_cons.1 hc with rfl | hrest
    · exact h.1
    · exact ih h.2 c hrest

/-- **Soundness of `wellFormedLayer`**: every comparator satisfies `i < j < n` and all
comparators in the layer act on pairwise disjoint wires. -/
theorem wellFormedLayer_sound (n : Nat) (layer : List (Nat × Nat))
    (h : wellFormedLayer n layer = true) :
    WellFormedLayer n layer := by
  simp only [wellFormedLayer, Bool.and_eq_true] at h
  exact ⟨wellFormed_sound n layer h.1, layerDisjoint_sound layer h.2⟩

/-- **Soundness of `wellFormedLayers`**: every layer in `layers` satisfies `WellFormedLayer`. -/
theorem wellFormedLayers_sound (n : Nat) (layers : List (List (Nat × Nat)))
    (h : wellFormedLayers n layers = true) :
    WellFormedLayers n layers := by
  induction layers with
  | nil => intro layer hl; cases hl
  | cons layer rest ih =>
    simp only [wellFormedLayers, Bool.and_eq_true] at h
    intro l hl
    rcases List.mem_cons.1 hl with rfl | hrest
    · exact wellFormedLayer_sound n l h.1
    · exact ih h.2 l hrest

theorem applyComp_comm {α : Type} {n : Nat} (le : α → α → Bool)
    {i₁ j₁ i₂ j₂ : Nat} (hdisj : CompsDisjoint (i₁, j₁) (i₂, j₂))
    (v : Fin n → α) (k : Fin n) :
    applyComp le i₂ j₂ (applyComp le i₁ j₁ v) k =
      applyComp le i₁ j₁ (applyComp le i₂ j₂ v) k := by
  rcases hdisj with ⟨h11, h12, h21, h22⟩
  dsimp only at h11 h12 h21 h22
  unfold applyComp
  split
  · next h2 =>
    split
    · next h1 =>
      dsimp only
      have hij1 : j₁ ≠ i₁ := by omega
      have hij2 : j₂ ≠ i₂ := by omega
      have hne21 : i₂ ≠ i₁ := Ne.symm h11
      have hne22 : i₂ ≠ j₁ := Ne.symm h21
      have hnej21 : j₂ ≠ i₁ := Ne.symm h12
      have hnej22 : j₂ ≠ j₁ := Ne.symm h22
      simp only [hne21, hne22, hnej21, hnej22, h11, h12, h21, h22, ite_false]
      by_cases hk1 : k.val = i₁
      · simp only [hk1, h11, h12, ite_true, ite_false]
      · by_cases hk2 : k.val = j₁
        · simp only [hk2, h21, h22, hij1, ite_true, ite_false]
        · by_cases hk3 : k.val = i₂
          · simp only [hk3, hne21, hne22, ite_true, ite_false]
          · by_cases hk4 : k.val = j₂
            · simp only [hk4, hnej21, hnej22, hij2, ite_true, ite_false]
            · simp only [hk1, hk2, hk3, hk4, ite_false]
    · rfl
  · split
    · rfl
    · rfl

theorem applyLayer_untouched {α : Type} {n : Nat} (le : α → α → Bool)
    (layer : List (Nat × Nat)) (v : Fin n → α) (k : Fin n)
    (hk : k.val ∉ layerWires layer) :
    applyLayer le layer v k = v k := by
  induction layer generalizing v with
  | nil => rfl
  | cons c rest ih =>
    rcases c with ⟨i, j⟩
    simp only [layerWires, List.mem_cons, not_or] at hk
    rcases hk with ⟨hki, hkj, hrest⟩
    change applyLayer le rest (applyComp le i j v) k = v k
    rw [ih (applyComp le i j v) hrest]
    unfold applyComp
    split
    · simp only [hki, hkj, ite_false]
    · rfl

/-- **Simultaneous 1-clock-cycle parallel semantics**: for any well-formed layer `layer`,
`applyLayer le layer v` updates every matched pair `(i, j) ∈ layer` to `(min(v i, v j),
max(v i, v j))` simultaneously from the pre-layer state `v`, and leaves every unmatched
wire unchanged. -/
theorem applyLayer_parallel_spec {α : Type} {n : Nat} (le : α → α → Bool)
    (layer : List (Nat × Nat)) (hwf : WellFormedLayer n layer) (v : Fin n → α) :
    (∀ i j : Nat, (i, j) ∈ layer → ∀ (hi : i < n) (hj : j < n),
      applyLayer le layer v ⟨i, hi⟩ = cmpMin le (v ⟨i, hi⟩) (v ⟨j, hj⟩) ∧
      applyLayer le layer v ⟨j, hj⟩ = cmpMax le (v ⟨i, hi⟩) (v ⟨j, hj⟩)) ∧
    (∀ k : Fin n, k.val ∉ layerWires layer → applyLayer le layer v k = v k) := by
  refine ⟨?_, fun k hk => applyLayer_untouched le layer v k hk⟩
  induction layer generalizing v with
  | nil => intro _ _ hmem; cases hmem
  | cons c rest ih =>
    rcases c with ⟨a, b⟩
    rcases hwf with ⟨hbounds, ⟨hneq, hpw⟩⟩
    rcases List.pairwise_cons.1 hpw with ⟨hdisj_ab, hpw_rest⟩
    have hab_bounds : a < b ∧ b < n := hbounds (a, b) (by simp)
    have hwf_rest : WellFormedLayer n rest := by
      refine ⟨fun p hp => hbounds p (List.mem_cons_of_mem _ hp),
              ⟨fun p hp => hneq p (List.mem_cons_of_mem _ hp), hpw_rest⟩⟩
    have ha_not_in : a ∉ layerWires rest := by
      intro ha
      have : ∀ l : List (Nat × Nat), (∀ p ∈ l, a ≠ p.1 ∧ a ≠ p.2) → a ∉ layerWires l := by
        intro l
        induction l with
        | nil => intro _ h; cases h
        | cons q qs ihq =>
          rcases q with ⟨x, y⟩
          intro hq hmem
          have hxy := hq (x, y) (by simp)
          simp only [layerWires, List.mem_cons] at hmem
          rcases hmem with rfl | rfl | htail
          · exact hxy.1 rfl
          · exact hxy.2 rfl
          · exact ihq (fun p hp => hq p (List.mem_cons_of_mem _ hp)) htail
      exact this rest (fun p hp => let h := hdisj_ab p hp; ⟨h.1, h.2.1⟩) ha
    have hb_not_in : b ∉ layerWires rest := by
      intro hb
      have : ∀ l : List (Nat × Nat), (∀ p ∈ l, b ≠ p.1 ∧ b ≠ p.2) → b ∉ layerWires l := by
        intro l
        induction l with
        | nil => intro _ h; cases h
        | cons q qs ihq =>
          rcases q with ⟨x, y⟩
          intro hq hmem
          have hxy := hq (x, y) (by simp)
          simp only [layerWires, List.mem_cons] at hmem
          rcases hmem with rfl | rfl | htail
          · exact hxy.1 rfl
          · exact hxy.2 rfl
          · exact ihq (fun p hp => hq p (List.mem_cons_of_mem _ hp)) htail
      exact this rest (fun p hp => let h := hdisj_ab p hp; ⟨h.2.2.1, h.2.2.2⟩) hb
    intro i j hij hi hj
    change applyLayer le rest (applyComp le a b v) ⟨i, hi⟩ = _ ∧
      applyLayer le rest (applyComp le a b v) ⟨j, hj⟩ = _
    rcases List.mem_cons.1 hij with heq | hrest
    · cases heq
      have hba : b ≠ a := by omega
      constructor
      · rw [applyLayer_untouched le rest (applyComp le a b v) ⟨a, hi⟩ ha_not_in]
        simp only [applyComp, hab_bounds.1, hab_bounds.2, and_self, dite_true, ite_true]
      · rw [applyLayer_untouched le rest (applyComp le a b v) ⟨b, hj⟩ hb_not_in]
        simp only [applyComp, hab_bounds.1, hab_bounds.2, and_self, dite_true, hba, ite_false, ite_true]
    · have hdisj_p := hdisj_ab (i, j) hrest
      rcases hdisj_p with ⟨hai, haj, hbi, hbj⟩
      dsimp only at hai haj hbi hbj
      have hia : i ≠ a := Ne.symm hai
      have hib : i ≠ b := Ne.symm hbi
      have hja : j ≠ a := Ne.symm haj
      have hjb : j ≠ b := Ne.symm hbj
      have hvi : applyComp le a b v ⟨i, hi⟩ = v ⟨i, hi⟩ := by
        simp only [applyComp, hab_bounds.1, hab_bounds.2, and_self, dite_true, hia, hib, ite_false]
      have hvj : applyComp le a b v ⟨j, hj⟩ = v ⟨j, hj⟩ := by
        simp only [applyComp, hab_bounds.1, hab_bounds.2, and_self, dite_true, hja, hjb, ite_false]
      have hrec := ih hwf_rest (applyComp le a b v) i j hrest hi hj
      rw [hvi, hvj] at hrec
      exact hrec

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

theorem applyLayers_ext {α : Type} {n : Nat} (le : α → α → Bool)
    (layers : List (List (Nat × Nat))) {v₁ v₂ : Fin n → α} (h : ∀ k, v₁ k = v₂ k) :
    ∀ k, applyLayers le layers v₁ k = applyLayers le layers v₂ k := by
  induction layers generalizing v₁ v₂ with
  | nil => exact h
  | cons layer rest ih =>
    exact ih (applyNet_ext le layer h)

theorem applyNet_append {α : Type} {n : Nat} (le : α → α → Bool)
    (xs ys : List (Nat × Nat)) (v : Fin n → α) :
    applyNet le (xs ++ ys) v = applyNet le ys (applyNet le xs v) := by
  induction xs generalizing v with
  | nil => rfl
  | cons c rest ih =>
    rcases c with ⟨i, j⟩
    exact ih (applyComp le i j v)

theorem applyLayers_eq_applyNet_flatten {α : Type} {n : Nat} (le : α → α → Bool)
    (layers : List (List (Nat × Nat))) (v : Fin n → α) :
    applyLayers le layers v = applyNet le (flattenLayers layers) v := by
  induction layers generalizing v with
  | nil => rfl
  | cons layer rest ih =>
    simp only [applyLayers, applyLayer, flattenLayers, applyNet_append]
    exact ih (applyNet le layer v)

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

/-- **Zero-One Principle for parallel-layered networks**: if `layers` sorts every Boolean
input vector, then `layers` sorts every input vector over every decidable linear order. -/
theorem zero_one_principle_layers {n : Nat} (layers : List (List (Nat × Nat)))
    (hbool : ∀ v : Fin n → Bool, IsSortedBool (applyLayersBool layers v)) :
    ∀ {α : Type} (le : α → α → Bool), IsLinearOrder le →
      ∀ v : Fin n → α, IsSorted le (applyLayers le layers v) := by
  intro α le hlo v
  rw [applyLayers_eq_applyNet_flatten]
  apply zero_one_principle (flattenLayers layers)
  · intro b
    have hb := hbool b
    unfold applyLayersBool at hb
    rw [applyLayers_eq_applyNet_flatten] at hb
    exact hb
  · exact hlo

/-! ## Mission target predicate -/

/-- Existence of a well-formed parallel sorting network on `n` wires of depth `d`
(`d` layers of in-bounds, pairwise-disjoint comparators) that sorts every input vector
over every decidable linear order `(α, le)`. -/
def ValidParallelSortingNetwork (n d : Nat) : Prop :=
  ∃ layers : List (List (Nat × Nat)),
    WellFormedLayers n layers ∧
    layers.length = d ∧
    ∀ {α : Type} (le : α → α → Bool), IsLinearOrder le →
      ∀ v : Fin n → α, IsSorted le (applyLayers le layers v)

/-- Standard decidable order on `Nat`. -/
def leNat (a b : Nat) : Bool := Nat.ble a b

theorem isLinearOrder_leNat : IsLinearOrder leNat where
  refl x := by simp [leNat]
  trans x y z hxy hyz := by
    simp only [leNat, Nat.ble_eq] at hxy hyz ⊢
    omega
  total x y := by
    simp only [leNat, Nat.ble_eq]
    omega

/-- Corollary: every `ValidParallelSortingNetwork n d` witnesses a depth-`d` disjoint-layer
network that sorts every natural-number vector `v : Fin n → Nat`. -/
theorem validParallelSortingNetwork_sorts_nat {n d : Nat}
    (h : ValidParallelSortingNetwork n d) :
    ∃ layers : List (List (Nat × Nat)),
      WellFormedLayers n layers ∧
      layers.length = d ∧
      ∀ v : Fin n → Nat, IsSorted leNat (applyLayers leNat layers v) := by
  rcases h with ⟨layers, hwf, hlen, hsorts⟩
  exact ⟨layers, hwf, hlen, hsorts leNat isLinearOrder_leNat⟩

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

/-- Apply a comparator list in parallel across all `2^n` inputs via bitwise AND/OR. -/
def evalNetBits (w : List Nat) : List (Nat × Nat) → List Nat
  | [] => w
  | (i, j) :: rest =>
    let a := getWire w i
    let b := getWire w j
    evalNetBits (setWire (setWire w i (a &&& b)) j (a ||| b)) rest

/-- Apply a sequence of parallel layers in bit-sliced form across all `2^n` inputs. -/
def evalLayersBits (w : List Nat) : List (List (Nat × Nat)) → List Nat
  | [] => w
  | layer :: rest => evalLayersBits (evalNetBits w layer) rest

/-- Check that every adjacent wire pair satisfies `w_i ≤ w_{i+1}` at every bit position
(`w_i ||| w_{i+1} == w_{i+1}`, i.e., never `1` before `0`). -/
def sortedWires : List Nat → Bool
  | [] => true
  | [_] => true
  | a :: b :: rest => ((a ||| b) == b) && sortedWires (b :: rest)

/-- Kernel-decidable bit-sliced verifier testing all `2^n` Boolean inputs in a single pass. -/
def checkSortLayers (n : Nat) (layers : List (List (Nat × Nat))) : Bool :=
  sortedWires (evalLayersBits (initWiresBits n) layers)

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

theorem length_evalLayersBits (w : List Nat) (layers : List (List (Nat × Nat))) :
    (evalLayersBits w layers).length = w.length := by
  induction layers generalizing w with
  | nil => rfl
  | cons layer rest ih =>
    simp only [evalLayersBits]
    rw [ih, length_evalNetBits]

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

theorem evalLayersBits_testBit {n : Nat} (layers : List (List (Nat × Nat))) (w : List Nat) (m : Nat)
    (hlen : w.length = n) (hwf : wellFormedLayers n layers = true) :
    ∀ k : Fin n, (getWire (evalLayersBits w layers) k.val).testBit m =
      applyLayersBool layers (fun idx : Fin n => (getWire w idx.val).testBit m) k := by
  induction layers generalizing w with
  | nil => intro k; rfl
  | cons layer rest ih =>
    simp only [wellFormedLayers, wellFormedLayer, Bool.and_eq_true] at hwf
    rcases hwf with ⟨⟨hwf_layer, _⟩, hwf_rest⟩
    intro k
    simp only [evalLayersBits, applyLayersBool, applyLayers]
    have hlen' : (evalNetBits w layer).length = n := by
      rw [length_evalNetBits, hlen]
    rw [ih (evalNetBits w layer) hlen' hwf_rest k]
    apply applyLayers_ext leBool rest
    intro idx
    exact evalNetBits_testBit layer w m hlen hwf_layer idx

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

/-- **Soundness of `checkSortLayers`**: if `layers` is well-formed on `n` wires and passes
the bit-sliced kernel check `checkSortLayers n layers = true`, then `layers` sorts every
Boolean input `v : Fin n → Bool`. -/
theorem checkSortLayers_sound (n : Nat) (layers : List (List (Nat × Nat)))
    (hwf : wellFormedLayers n layers = true) (hchk : checkSortLayers n layers = true) :
    ∀ v : Fin n → Bool, IsSortedBool (applyLayersBool layers v) := by
  intro v
  let m := encodeBits v
  have hm : m < 2 ^ n := encodeBitsAux_lt v n (Nat.le_refl n)
  have hlen0 : (initWiresBits n).length = n := by simp [initWiresBits]
  have hlenF : (evalLayersBits (initWiresBits n) layers).length = n := by
    rw [length_evalLayersBits, hlen0]
  have hinit : ∀ idx : Fin n, (getWire (initWiresBits n) idx.val).testBit m = v idx := by
    intro idx
    rw [getWire_initWiresBits n idx.val idx.isLt, wireMask_testBit n idx.val m idx.isLt hm]
    exact encodeBitsAux_testBit v n (Nat.le_refl n) idx.val idx.isLt
  have heval : ∀ k : Fin n,
      (getWire (evalLayersBits (initWiresBits n) layers) k.val).testBit m =
        applyLayersBool layers v k := by
    intro k
    rw [evalLayersBits_testBit layers (initWiresBits n) m hlen0 hwf k]
    exact applyLayers_ext leBool layers hinit k
  apply isSortedBool_of_adj
  intro i hi
  have hadj := sortedWires_adj (evalLayersBits (initWiresBits n) layers) hchk i (by rw [hlenF]; exact hi)
  have htb : ((getWire (evalLayersBits (initWiresBits n) layers) i) |||
      (getWire (evalLayersBits (initWiresBits n) layers) (i + 1))).testBit m =
      (getWire (evalLayersBits (initWiresBits n) layers) (i + 1)).testBit m :=
    congrArg (fun x => x.testBit m) hadj
  rw [Nat.testBit_or, heval ⟨i, Nat.lt_of_succ_lt hi⟩, heval ⟨i + 1, hi⟩] at htb
  cases h1 : applyLayersBool layers v ⟨i, Nat.lt_of_succ_lt hi⟩ <;>
    cases h2 : applyLayersBool layers v ⟨i + 1, hi⟩
  · rfl
  · rfl
  · rw [h1, h2] at htb; cases htb
  · rfl

/-- End-to-end kernel certification bridge: well-formedness, depth equality, and the
bit-sliced Boolean check certify `ValidParallelSortingNetwork n d` over all linear orders. -/
theorem validParallelSortingNetwork_of_check (n d : Nat) (layers : List (List (Nat × Nat)))
    (hwf : wellFormedLayers n layers = true)
    (hlen : layers.length = d)
    (hchk : checkSortLayers n layers = true) :
    ValidParallelSortingNetwork n d :=
  ⟨layers, wellFormedLayers_sound n layers hwf, hlen,
    zero_one_principle_layers layers (checkSortLayers_sound n layers hwf hchk)⟩

end SortDepth
