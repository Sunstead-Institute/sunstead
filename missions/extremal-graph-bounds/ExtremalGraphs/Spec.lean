/-!
# Extremal Graphs: Ramsey Witness Frontiers & C4-Free Turán Bounds

This module formalizes two classical families of extremal graph witness problems in pure
Lean 4.36.0 (zero Mathlib, standard axioms only):

1. **Simple Undirected Graphs (`SimpleGraph n`)**: explicit symmetric, loopless adjacency
   relations on `Fin n`.
2. **Two-Color Classical Ramsey Lower Bounds (`ValidRamseyGraph s t N`)**: existence of a
   simple graph on `N` vertices containing neither an `s`-clique (`¬ HasClique G.adj s`) nor
   a `t`-independent set (`¬ HasIndep G.adj t`), certifying `R(s, t) ≥ N + 1`.
3. **C4-Free Extremal Graphs (`ValidC4FreeGraph n e`)**: existence of a simple graph on `n`
   vertices with `e` undirected edges and no 4-cycle (`¬ HasC4 G.adj`), certifying
   `ex(n, C_4) ≥ e`.
4. **Proved-Sound Fast Bitmask Kernel Verifiers**:
   - Active-filtered Tomita greedy-coloring branch-and-bound clique checker (`noClique`,
     proved completely sound in `noClique_sound` and `validRamseyGraph_of_check`).
   - Constant-time per-pair bitwise common-neighbor `C_4`-freeness checker (`checkC4Free`,
     testing `(m &&& (m - 1)) == 0`, proved sound in `checkC4Free_sound` and
     `validC4FreeGraph_of_check`).

Upstream Ramsey witness records and Radziszowski survey lower bounds are pinned to
`chrispbsmolen/ramsey-witnesses` at commit `d21fda594c86657be87e425f19f5fc02a27986e6` (MIT).
-/

namespace ExtremalGraphs

/-! ## Simple graphs, cliques, independent sets, and C4-freeness -/

/-- A simple undirected graph on `n` vertices (symmetric and loopless). -/
structure SimpleGraph (n : Nat) where
  adj : Fin n → Fin n → Bool
  symm : ∀ u v, adj u v = adj v u
  loopless : ∀ u, adj u u = false

/-- Existence of a `k`-clique in `adj`. -/
def HasClique {n : Nat} (adj : Fin n → Fin n → Bool) (k : Nat) : Prop :=
  ∃ f : Fin k → Fin n,
    (∀ a b : Fin k, a ≠ b → f a ≠ f b) ∧
    (∀ a b : Fin k, a ≠ b → adj (f a) (f b) = true)

/-- Existence of an independent set of size `k` in `adj`. -/
def HasIndep {n : Nat} (adj : Fin n → Fin n → Bool) (k : Nat) : Prop :=
  ∃ f : Fin k → Fin n,
    (∀ a b : Fin k, a ≠ b → f a ≠ f b) ∧
    (∀ a b : Fin k, a ≠ b → adj (f a) (f b) = false)

/-- Existence of a 4-cycle `a - b - c - d - a` of four pairwise distinct vertices. -/
def HasC4 {n : Nat} (adj : Fin n → Fin n → Bool) : Prop :=
  ∃ a b c d : Fin n,
    a ≠ b ∧ a ≠ c ∧ a ≠ d ∧ b ≠ c ∧ b ≠ d ∧ c ≠ d ∧
    adj a b = true ∧ adj b c = true ∧ adj c d = true ∧ adj d a = true

/-- Count neighbors `v` of `u` with `u < v < hi`. -/
def rowUpperEdges {n : Nat} (adj : Fin n → Fin n → Bool) (u : Fin n) :
    (hi : Nat) → hi ≤ n → Nat
  | 0, _ => 0
  | k + 1, hk =>
    rowUpperEdges adj u k (Nat.le_of_succ_le hk) +
      (if u.val < k && adj u ⟨k, hk⟩ then 1 else 0)

/-- Sum of upper-triangular edges over rows `0, ..., r - 1`. -/
def edgeCountAux {n : Nat} (adj : Fin n → Fin n → Bool) : (r : Nat) → r ≤ n → Nat
  | 0, _ => 0
  | r + 1, hr =>
    edgeCountAux adj r (Nat.le_of_succ_le hr) +
      rowUpperEdges adj ⟨r, hr⟩ n (Nat.le_refl n)

/-- Total number of undirected edges `{u, v}` (`u < v`) in a graph on `n` vertices. -/
def edgeCount {n : Nat} (adj : Fin n → Fin n → Bool) : Nat :=
  edgeCountAux adj n (Nat.le_refl n)

/-! ## Mission target predicates -/

/-- Existence of a simple graph on `N` vertices avoiding both `K_s` and independent sets
of size `t`, certifying the classical Ramsey lower bound `R(s, t) ≥ N + 1`. -/
def ValidRamseyGraph (s t N : Nat) : Prop :=
  ∃ G : SimpleGraph N, ¬ HasClique G.adj s ∧ ¬ HasIndep G.adj t

/-- Existence of a simple `C_4`-free graph on `n` vertices with `e` undirected edges,
certifying the Turán lower bound `ex(n, C_4) ≥ e`. -/
def ValidC4FreeGraph (n e : Nat) : Prop :=
  ∃ G : SimpleGraph n, edgeCount G.adj = e ∧ ¬ HasC4 G.adj

/-! ## Bitmask graph representation and checkers -/

def getRow : List Nat → Nat → Nat
  | [], _ => 0
  | x :: _, 0 => x
  | _ :: xs, i + 1 => getRow xs i

/-- Adjacency function decoded from a list of `n` neighbor bitmasks. -/
def rowsAdj (n : Nat) (rows : List Nat) : Fin n → Fin n → Bool :=
  fun u v => (getRow rows u.val).testBit v.val

/-- Check that every row mask fits in `n` bits and has no self-loop. -/
def checkRowsBasic (bound : Nat) : List Nat → Nat → Bool
  | [], _ => true
  | r :: rs, u => Nat.blt r bound && !(r.testBit u) && checkRowsBasic bound rs (u + 1)

/-- Check that `r_u.testBit v == r_v.testBit u` for all `v` in tail rows. -/
def checkSymmRow (u : Nat) (ru : Nat) : List Nat → Nat → Bool
  | [], _ => true
  | rv :: rest, v => (ru.testBit v == rv.testBit u) && checkSymmRow u ru rest (v + 1)

/-- Check symmetry across all pairs `u < v`. -/
def checkSymmAll : List Nat → Nat → Bool
  | [], _ => true
  | ru :: rest, u => checkSymmRow u ru rest (u + 1) && checkSymmAll rest (u + 1)

/-- Check that `rows` encodes a well-formed simple undirected graph on `n` vertices. -/
def checkSimpleGraph (n : Nat) (rows : List Nat) : Bool :=
  (rows.length == n) && checkRowsBasic (1 <<< n) rows 0 && checkSymmAll rows 0

/-- Build complement adjacency bitmasks for a graph on `n` vertices. -/
def compRowsAux (full : Nat) : List Nat → Nat → List Nat
  | [], _ => []
  | r :: rs, u => (full ^^^ r ^^^ (1 <<< u)) :: compRowsAux full rs (u + 1)

def compRows (n : Nat) (rows : List Nat) : List Nat :=
  compRowsAux ((1 <<< n) - 1) rows 0

/-- Index adjacency rows as `(vertexIndex, neighborMask)` pairs. -/
def toActive : List Nat → Nat → List (Nat × Nat)
  | [], _ => []
  | r :: rs, u => (u, r) :: toActive rs (u + 1)

/-- Restrict active vertex list to vertices present in `cand`. -/
def filterActive (cand : Nat) : List (Nat × Nat) → List (Nat × Nat)
  | [] => []
  | p :: ps =>
    if cand.testBit p.1 then p :: filterActive cand ps
    else filterActive cand ps

/-- Peel one maximal greedy independent set from `avail`, removing its vertices from `uncol`. -/
def peelOne : List (Nat × Nat) → Nat → Nat → Nat
  | [], _, uncol => uncol
  | (u, nb) :: rest, avail, uncol =>
    if avail == 0 then uncol
    else
      let bit := 1 <<< u
      if (avail &&& bit) == 0 then
        peelOne rest avail uncol
      else
        peelOne rest (avail &&& (avail ^^^ (nb ||| bit))) (uncol ^^^ bit)

/-- Peel `c` greedy independent sets from `rem`, returning the uncolored leftover mask. -/
def peelColors (active : List (Nat × Nat)) : Nat → Nat → Nat
  | 0, rem => rem
  | c + 1, rem =>
    if rem == 0 then 0
    else peelColors active c (peelOne active rem rem)

/-- Fast base check for absence of any edge (2-clique) inside `cand`. -/
def noClique2 : List (Nat × Nat) → Nat → Bool
  | [], _ => true
  | (u, nb) :: rest, cand =>
    if cand == 0 then true
    else
      let bit := 1 <<< u
      if (cand &&& bit) == 0 then
        noClique2 rest cand
      else
        let cand' := cand ^^^ bit
        ((cand' &&& nb) == 0) && noClique2 rest cand'

/-- Branch only over uncolored leftover vertices `r`, updating remaining candidates `c`. -/
def noCliqueBranch (recCheck : Nat → Bool) : List (Nat × Nat) → Nat → Nat → Bool
  | [], _, _ => true
  | (u, nb) :: rest, r, c =>
    if r == 0 then true
    else
      let bit := 1 <<< u
      if (r &&& bit) == 0 then
        noCliqueBranch recCheck rest r c
      else
        let c' := c ^^^ bit
        let r' := r ^^^ bit
        recCheck (c' &&& nb) && noCliqueBranch recCheck rest r' c'

/-- Active-filtered Tomita greedy-coloring clique-freeness checker. -/
def noClique (active : List (Nat × Nat)) : Nat → Nat → Bool
  | 0, _ => false
  | 1, cand => cand == 0
  | 2, cand => noClique2 active cand
  | k + 1, cand =>
    if cand == 0 then true
    else
      let act := filterActive cand active
      let rem := peelColors act k cand
      if rem == 0 then true
      else noCliqueBranch (noClique act k) act rem cand

/-- Check that `rows` has no `k`-clique on `n` vertices. -/
def checkNoClique (n k : Nat) (rows : List Nat) : Bool :=
  noClique (toActive rows 0) k ((1 <<< n) - 1)

/-- Check `C_4`-freeness for row `a` against all subsequent rows:
every pair of distinct vertices shares at most 1 common neighbor (`m &&& (m - 1) == 0`). -/
def c4FreeRow (a : Nat) : List Nat → Bool
  | [] => true
  | b :: bs =>
    let m := a &&& b
    ((m &&& (m - 1)) == 0) && c4FreeRow a bs

/-- Check that no pair of distinct rows shares `≥ 2` common neighbors (hence no `C_4`). -/
def checkC4Free : List Nat → Bool
  | [] => true
  | a :: rest => c4FreeRow a rest && checkC4Free rest

/-- Count bits `v` in `row` with `u < v < hi`. -/
def countRowUpperBits (row u : Nat) : Nat → Nat
  | 0 => 0
  | k + 1 => countRowUpperBits row u k + (if u < k && row.testBit k then 1 else 0)

/-- Count total undirected edges in `rows` over `n` vertices. -/
def countEdgesAux (n : Nat) : List Nat → Nat → Nat
  | [], _ => 0
  | r :: rs, u => countRowUpperBits r u n + countEdgesAux n rs (u + 1)

def countEdges (n : Nat) (rows : List Nat) : Nat :=
  countEdgesAux n rows 0

/-! ## Soundness proofs -/

/-! ### SimpleGraph & complement soundness -/

theorem getRow_eq_getD (rows : List Nat) (i : Nat) : getRow rows i = rows.getD i 0 := by
  induction rows generalizing i with
  | nil => simp [getRow]
  | cons x xs ih =>
    cases i with
    | zero => rfl
    | succ i => exact ih i

theorem checkRowsBasic_sound (bound : Nat) (rows : List Nat) (u0 : Nat)
    (h : checkRowsBasic bound rows u0 = true) :
    ∀ k, k < rows.length →
      getRow rows k < bound ∧ (getRow rows k).testBit (u0 + k) = false := by
  induction rows generalizing u0 with
  | nil => intro k hk; cases hk
  | cons r rs ih =>
    simp only [checkRowsBasic, Bool.and_eq_true, Nat.blt_eq, Bool.not_eq_true'] at h
    intro k hk
    cases k with
    | zero => simpa [getRow] using h.1
    | succ k =>
      have hk' : k < rs.length := Nat.lt_of_succ_lt_succ hk
      have hrec := ih (u0 + 1) h.2 k hk'
      have heq : u0 + 1 + k = u0 + (k + 1) := by omega
      rw [heq] at hrec
      exact hrec

theorem checkSymmRow_sound (u ru : Nat) (rest : List Nat) (v0 : Nat)
    (h : checkSymmRow u ru rest v0 = true) :
    ∀ k, k < rest.length → ru.testBit (v0 + k) = (getRow rest k).testBit u := by
  induction rest generalizing v0 with
  | nil => intro k hk; cases hk
  | cons rv rs ih =>
    simp only [checkSymmRow, Bool.and_eq_true, beq_iff_eq] at h
    intro k hk
    cases k with
    | zero => simpa [getRow] using h.1
    | succ k =>
      have hk' : k < rs.length := Nat.lt_of_succ_lt_succ hk
      have hrec := ih (v0 + 1) h.2 k hk'
      have heq : v0 + 1 + k = v0 + (k + 1) := by omega
      rw [heq] at hrec
      exact hrec

theorem checkSymmAll_sound (rows : List Nat) (u0 : Nat)
    (h : checkSymmAll rows u0 = true) :
    ∀ i j, i < j → j < rows.length →
      (getRow rows i).testBit (u0 + j) = (getRow rows j).testBit (u0 + i) := by
  induction rows generalizing u0 with
  | nil => intro i j _ hj; cases hj
  | cons ru rest ih =>
    simp only [checkSymmAll, Bool.and_eq_true] at h
    intro i j hij hj
    cases i with
    | zero =>
      cases j with
      | zero => omega
      | succ j =>
        have hj' : j < rest.length := Nat.lt_of_succ_lt_succ hj
        have hrow := checkSymmRow_sound u0 ru rest (u0 + 1) h.1 j hj'
        have heq : u0 + 1 + j = u0 + (j + 1) := by omega
        rw [heq] at hrow
        simpa [getRow] using hrow
    | succ i =>
      cases j with
      | zero => omega
      | succ j =>
        have hrec := ih (u0 + 1) h.2 i j (Nat.lt_of_succ_lt_succ hij) (Nat.lt_of_succ_lt_succ hj)
        have heq1 : u0 + 1 + j = u0 + (j + 1) := by omega
        have heq2 : u0 + 1 + i = u0 + (i + 1) := by omega
        rw [heq1, heq2] at hrec
        exact hrec

theorem simpleGraph_of_check (n : Nat) (rows : List Nat) (h : checkSimpleGraph n rows = true) :
    rows.length = n ∧
    (∀ u : Fin n, getRow rows u.val < 2 ^ n) ∧
    (∀ u : Fin n, rowsAdj n rows u u = false) ∧
    (∀ u v : Fin n, rowsAdj n rows u v = rowsAdj n rows v u) := by
  simp only [checkSimpleGraph, Bool.and_eq_true, beq_iff_eq] at h
  rcases h with ⟨⟨hlen, hbasic⟩, hsymm⟩
  have hpow : (1 <<< n) = 2 ^ n := by rw [Nat.shiftLeft_eq, Nat.one_mul]
  rw [hpow] at hbasic
  have hb := checkRowsBasic_sound (2 ^ n) rows 0 hbasic
  have hs := checkSymmAll_sound rows 0 hsymm
  refine ⟨hlen, ?_, ?_, ?_⟩
  · intro u
    exact (hb u.val (by rw [hlen]; exact u.isLt)).1
  · intro u
    have h0 := (hb u.val (by rw [hlen]; exact u.isLt)).2
    simpa [rowsAdj] using h0
  · intro u v
    unfold rowsAdj
    by_cases hlt : u.val < v.val
    · have := hs u.val v.val hlt (by rw [hlen]; exact v.isLt)
      simpa using this
    · by_cases heq : u.val = v.val
      · rw [heq]
      · have hgt : v.val < u.val := by omega
        have := hs v.val u.val hgt (by rw [hlen]; exact u.isLt)
        simpa using this.symm

def mkSimpleGraph (n : Nat) (rows : List Nat) (h : checkSimpleGraph n rows = true) : SimpleGraph n :=
  let hc := simpleGraph_of_check n rows h
  { adj := rowsAdj n rows
    symm := hc.2.2.2
    loopless := hc.2.2.1 }

theorem getRow_compRowsAux (full : Nat) (rows : List Nat) (u0 k : Nat) (hk : k < rows.length) :
    getRow (compRowsAux full rows u0) k = full ^^^ getRow rows k ^^^ (1 <<< (u0 + k)) := by
  induction rows generalizing u0 k with
  | nil => cases hk
  | cons r rs ih =>
    cases k with
    | zero => simp [compRowsAux, getRow]
    | succ k =>
      simp only [compRowsAux, getRow]
      rw [ih (u0 + 1) k (Nat.lt_of_succ_lt_succ hk)]
      have heq : u0 + 1 + k = u0 + (k + 1) := by omega
      rw [heq]

theorem compRows_length (n : Nat) (rows : List Nat) : (compRows n rows).length = rows.length := by
  unfold compRows
  have aux : ∀ full u0 (rs : List Nat), (compRowsAux full rs u0).length = rs.length := by
    intro full u0 rs
    induction rs generalizing u0 with
    | nil => rfl
    | cons _ _ ih => simp [compRowsAux, ih]
  exact aux _ 0 rows

theorem compRows_testBit (n : Nat) (rows : List Nat) (hlen : rows.length = n)
    (hloop : ∀ u : Fin n, rowsAdj n rows u u = false) (u v : Fin n) :
    (getRow (compRows n rows) u.val).testBit v.val =
      ((u.val != v.val) && !(rowsAdj n rows u v)) := by
  unfold compRows rowsAdj
  rw [getRow_compRowsAux ((1 <<< n) - 1) rows 0 u.val (by rw [hlen]; exact u.isLt)]
  have hpow : (1 <<< n) = 2 ^ n := by rw [Nat.shiftLeft_eq, Nat.one_mul]
  have hbit : (1 <<< (0 + u.val)) = 2 ^ u.val := by
    rw [Nat.zero_add, Nat.shiftLeft_eq, Nat.one_mul]
  rw [hpow, hbit, Nat.testBit_xor, Nat.testBit_xor, Nat.testBit_two_pow_sub_one, Nat.testBit_two_pow]
  have hv : v.val < n := v.isLt
  by_cases huv : u.val = v.val
  · have hu_eq : u = v := Fin.ext huv
    subst hu_eq
    have hl : (getRow rows u.val).testBit u.val = false := hloop u
    simp [hv, hl]
  · have hne' : (u.val != v.val) = true := bne_iff_ne.2 huv
    have hdec : decide (u.val = v.val) = false := decide_eq_false huv
    have hlt_dec : decide (v.val < n) = true := decide_eq_true hv
    rw [hlt_dec, hdec, hne']
    cases (getRow rows u.val).testBit v.val <;> rfl

/-! ### Bitmask clique & Tomita greedy-coloring soundness -/

/-- `f : Fin k → Fin n` is a `k`-clique in `adj` with all vertices contained in bitmask `cand`. -/
def IsCliqueIn {n : Nat} (adj : Fin n → Fin n → Bool) (cand : Nat) (k : Nat) : Prop :=
  ∃ f : Fin k → Fin n,
    (∀ a : Fin k, cand.testBit (f a).val = true) ∧
    (∀ a b : Fin k, a ≠ b → f a ≠ f b) ∧
    (∀ a b : Fin k, a ≠ b → adj (f a) (f b) = true)

/-- Every `(u, nb)` in `active` has `u < n` and exact neighbor bitmask for `adj`. -/
def ActiveValid {n : Nat} (adj : Fin n → Fin n → Bool) (active : List (Nat × Nat)) : Prop :=
  ∀ p ∈ active, ∃ hu : p.1 < n, ∀ v : Fin n, p.2.testBit v.val = adj ⟨p.1, hu⟩ v

/-- Every vertex set in `mask` appears in `active`. -/
def ActiveCover (n : Nat) (active : List (Nat × Nat)) (mask : Nat) : Prop :=
  ∀ u : Fin n, mask.testBit u.val = true → ∃ nb, (u.val, nb) ∈ active

/-- Remove index `a` from a `Fin (k + 1)` indexing function. -/
def skipIdx {k : Nat} (a : Fin (k + 1)) (i : Fin k) : Fin (k + 1) :=
  if h : i.val < a.val then ⟨i.val, Nat.lt_trans h a.isLt⟩
  else ⟨i.val + 1, Nat.succ_lt_succ i.isLt⟩

theorem skipIdx_ne {k : Nat} (a : Fin (k + 1)) (i : Fin k) : skipIdx a i ≠ a := by
  unfold skipIdx
  split
  · intro heq; have := congrArg Fin.val heq; dsimp only at this; omega
  · intro heq; have := congrArg Fin.val heq; dsimp only at this; omega

theorem skipIdx_inj {k : Nat} (a : Fin (k + 1)) {i j : Fin k} (hij : i ≠ j) :
    skipIdx a i ≠ skipIdx a j := by
  have hne : i.val ≠ j.val := fun h => hij (Fin.ext h)
  unfold skipIdx
  split <;> split <;> intro heq <;> have hval := congrArg Fin.val heq <;> dsimp only at hval <;> omega

theorem toActive_valid {n : Nat} (adj : Fin n → Fin n → Bool) (rows : List Nat) (u0 : Nat)
    (hrows : ∀ k, k < rows.length → ∃ hu : u0 + k < n,
      ∀ v : Fin n, (getRow rows k).testBit v.val = adj ⟨u0 + k, hu⟩ v) :
    ActiveValid adj (toActive rows u0) := by
  induction rows generalizing u0 with
  | nil => intro p hp; cases hp
  | cons r rs ih =>
    intro p hp
    rcases List.mem_cons.1 hp with rfl | hrest
    · simpa [getRow] using hrows 0 (by simp)
    · apply ih (u0 + 1) ?_ p hrest
      intro k hk
      have hrec := hrows (k + 1) (Nat.succ_lt_succ hk)
      have heq : u0 + (k + 1) = u0 + 1 + k := by omega
      rcases hrec with ⟨hu, hadj⟩
      exact ⟨heq ▸ hu, fun v => by simpa [getRow, heq] using hadj v⟩

theorem toActive_cover (n : Nat) (rows : List Nat) (u0 : Nat) (hlen : u0 + rows.length = n) :
    ∀ u : Fin n, u0 ≤ u.val → ∃ nb, (u.val, nb) ∈ toActive rows u0 := by
  induction rows generalizing u0 with
  | nil => intro u hu; simp at hlen; have := u.isLt; omega
  | cons r rs ih =>
    intro u hu
    by_cases heq : u.val = u0
    · refine ⟨r, ?_⟩
      rw [heq]; simp [toActive]
    · have hrec := ih (u0 + 1) (by simp at hlen; omega) u (by omega)
      rcases hrec with ⟨nb, hmem⟩
      exact ⟨nb, List.mem_cons_of_mem _ hmem⟩

theorem filterActive_valid {n : Nat} {adj : Fin n → Fin n → Bool}
    (cand : Nat) (active : List (Nat × Nat)) (hv : ActiveValid adj active) :
    ActiveValid adj (filterActive cand active) := by
  induction active with
  | nil => intro p hp; cases hp
  | cons p ps ih =>
    intro q hq
    simp only [filterActive] at hq
    split at hq
    · rcases List.mem_cons.1 hq with rfl | hrest
      · exact hv q (by simp)
      · exact ih (fun x hx => hv x (List.mem_cons_of_mem _ hx)) q hrest
    · exact ih (fun x hx => hv x (List.mem_cons_of_mem _ hx)) q hq

theorem filterActive_cover {n : Nat} (cand : Nat) (active : List (Nat × Nat))
    (hc : ActiveCover n active cand) :
    ActiveCover n (filterActive cand active) cand := by
  intro u hu
  rcases hc u hu with ⟨nb, hmem⟩
  refine ⟨nb, ?_⟩
  have aux : ∀ l : List (Nat × Nat), (u.val, nb) ∈ l → (u.val, nb) ∈ filterActive cand l := by
    intro l hl
    induction l with
    | nil => cases hl
    | cons p ps ih =>
      simp only [filterActive]
      rcases List.mem_cons.1 hl with rfl | hrest
      · simp [hu]
      · split
        · exact List.mem_cons_of_mem _ (ih hrest)
        · exact ih hrest
  exact aux active hmem

private theorem testBit_and_xor_clear (a x i : Nat) :
    (a &&& (a ^^^ x)).testBit i = (a.testBit i && !(x.testBit i)) := by
  rw [Nat.testBit_and, Nat.testBit_xor]
  cases a.testBit i <;> cases x.testBit i <;> rfl

/-- Core invariant for `peelOne`: every vertex cleared from `uncol` comes from `avail`,
is cleared at most once, and the cleared set is an independent set of `adj`. -/
theorem peelOne_sound {n : Nat} {adj : Fin n → Fin n → Bool}
    (hsymm : ∀ u v, adj u v = adj v u)
    (active : List (Nat × Nat)) (hv : ActiveValid adj active)
    (avail uncol : Nat)
    (hsub : ∀ i, avail.testBit i = true → uncol.testBit i = true) :
    (∀ i, (peelOne active avail uncol).testBit i = true → uncol.testBit i = true) ∧
    (∀ i, uncol.testBit i = true → (peelOne active avail uncol).testBit i = false →
      avail.testBit i = true) ∧
    (∀ x y : Fin n,
      uncol.testBit x.val = true → (peelOne active avail uncol).testBit x.val = false →
      uncol.testBit y.val = true → (peelOne active avail uncol).testBit y.val = false →
      x ≠ y → adj x y = false) := by
  induction active generalizing avail uncol with
  | nil =>
    refine ⟨fun _ h => h, (fun _ hu hf => by rw [peelOne] at hf; rw [hu] at hf; cases hf), ?_⟩
    intro x _ hx hxf
    rw [peelOne] at hxf; rw [hx] at hxf; cases hxf
  | cons p rest ih =>
    rcases p with ⟨u, nb⟩
    have hv_u := hv (u, nb) (by simp)
    rcases hv_u with ⟨hu_lt, hnb⟩
    have hv_rest : ActiveValid adj rest := fun q hq => hv q (List.mem_cons_of_mem _ hq)
    simp only [peelOne]
    by_cases hav0 : avail = 0
    · simp only [hav0, beq_self_eq_true, ↓reduceIte]
      refine ⟨fun _ h => h, (fun _ hu hf => by rw [hu] at hf; cases hf), ?_⟩
      intro x _ hx hxf; rw [hx] at hxf; cases hxf
    · have hav0_f : (avail == 0) = false := beq_false_of_ne hav0
      simp only [hav0_f, Bool.false_eq_true, ↓reduceIte]
      have hbit_eq : (1 <<< u) = 2 ^ u := by rw [Nat.shiftLeft_eq, Nat.one_mul]
      by_cases hmem : (avail &&& (1 <<< u)) = 0
      · simp only [hmem, beq_self_eq_true, ↓reduceIte]
        exact ih hv_rest avail uncol hsub
      · have hmem_f : ((avail &&& (1 <<< u)) == 0) = false := beq_false_of_ne hmem
        simp only [hmem_f, Bool.false_eq_true, ↓reduceIte]
        have hav_u : avail.testBit u = true := by
          cases htu : avail.testBit u
          · exfalso; apply hmem
            apply Nat.eq_of_testBit_eq
            intro i
            rw [Nat.testBit_and, hbit_eq, Nat.testBit_two_pow]
            by_cases hi : u = i
            · subst hi; simp [htu]
            · simp [hi]
          · rfl
        let avail' := avail &&& (avail ^^^ (nb ||| (1 <<< u)))
        let uncol' := uncol ^^^ (1 <<< u)
        have huncol'_tb : ∀ i, uncol'.testBit i = (if i = u then !(uncol.testBit i) else uncol.testBit i) := by
          intro i
          simp only [uncol', Nat.testBit_xor, hbit_eq, Nat.testBit_two_pow]
          by_cases hi : i = u
          · subst hi; simp
          · simp [hi, Ne.symm hi]
        have havail'_tb : ∀ i, avail'.testBit i =
            (avail.testBit i && !(nb.testBit i || decide (u = i))) := by
          intro i
          simp only [avail', testBit_and_xor_clear, Nat.testBit_or, hbit_eq, Nat.testBit_two_pow]
        have hsub' : ∀ i, avail'.testBit i = true → uncol'.testBit i = true := by
          intro i hi
          rw [havail'_tb] at hi
          simp only [Bool.and_eq_true, Bool.not_eq_true', Bool.or_eq_false_iff, decide_eq_false_iff_not] at hi
          rw [huncol'_tb]
          have hne : i ≠ u := Ne.symm hi.2.2
          simp [hne, hsub i hi.1]
        rcases ih hv_rest avail' uncol' hsub' with ⟨hih_sub, hih_av, hih_ind⟩
        have hun_u : uncol.testBit u = true := hsub u hav_u
        refine ⟨?_, ?_, ?_⟩
        · intro i hi
          have hu' := hih_sub i hi
          rw [huncol'_tb] at hu'
          by_cases hiu : i = u
          · subst hiu; rw [hun_u] at hu'; simp at hu'
          · simp [hiu] at hu'; exact hu'
        · intro i hui hfi
          by_cases hiu : i = u
          · subst hiu; exact hav_u
          · have hui' : uncol'.testBit i = true := by rw [huncol'_tb]; simp [hiu, hui]
            have hav' := hih_av i hui' hfi
            rw [havail'_tb] at hav'
            simp only [Bool.and_eq_true] at hav'
            exact hav'.1
        · intro x y hx hxf hy hyf hxy
          by_cases hxu : x.val = u
          · have hyu : y.val ≠ u := fun h => hxy (Fin.ext (by omega))
            have hy' : uncol'.testBit y.val = true := by rw [huncol'_tb]; simp [hyu, hy]
            have havy' := hih_av y.val hy' hyf
            rw [havail'_tb] at havy'
            simp only [Bool.and_eq_true, Bool.not_eq_true', Bool.or_eq_false_iff] at havy'
            have hx_eq : x = ⟨u, hu_lt⟩ := Fin.ext hxu
            rw [hx_eq, ← hnb y]
            exact havy'.2.1
          · by_cases hyu : y.val = u
            · have hx' : uncol'.testBit x.val = true := by rw [huncol'_tb]; simp [hxu, hx]
              have havx' := hih_av x.val hx' hxf
              rw [havail'_tb] at havx'
              simp only [Bool.and_eq_true, Bool.not_eq_true', Bool.or_eq_false_iff] at havx'
              have hy_eq : y = ⟨u, hu_lt⟩ := Fin.ext hyu
              rw [hsymm, hy_eq, ← hnb x]
              exact havx'.2.1
            · have hx' : uncol'.testBit x.val = true := by rw [huncol'_tb]; simp [hxu, hx]
              have hy' : uncol'.testBit y.val = true := by rw [huncol'_tb]; simp [hyu, hy]
              exact hih_ind x y hx' hxf hy' hyf hxy

theorem peelOne_clique_step {n : Nat} {adj : Fin n → Fin n → Bool}
    (hsymm : ∀ u v, adj u v = adj v u)
    (active : List (Nat × Nat)) (hv : ActiveValid adj active)
    (rem k : Nat) (hcl : IsCliqueIn adj rem (k + 1)) :
    IsCliqueIn adj (peelOne active rem rem) k := by
  rcases hcl with ⟨f, hmem, hinj, hadj⟩
  have hpeel := (peelOne_sound hsymm active hv rem rem (fun _ h => h)).2.2
  by_cases hex : ∃ a : Fin (k + 1), (peelOne active rem rem).testBit (f a).val = false
  · rcases hex with ⟨a, ha⟩
    refine ⟨fun i => f (skipIdx a i), ?_, ?_, ?_⟩
    · intro i
      cases htb : (peelOne active rem rem).testBit (f (skipIdx a i)).val
      · exfalso
        have hne_idx : skipIdx a i ≠ a := skipIdx_ne a i
        have hne_v : f (skipIdx a i) ≠ f a := hinj _ _ hne_idx
        have hfalse := hpeel (f (skipIdx a i)) (f a) (hmem _) htb (hmem _) ha hne_v
        have htrue := hadj _ _ hne_idx
        rw [hfalse] at htrue; cases htrue
      · rfl
    · intro i j hij
      exact hinj _ _ (skipIdx_inj a hij)
    · intro i j hij
      exact hadj _ _ (skipIdx_inj a hij)
  · refine ⟨fun i => f ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩, ?_, ?_, ?_⟩
    · intro i
      cases htb : (peelOne active rem rem).testBit (f ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩).val
      · exact False.elim (hex ⟨⟨i.val, Nat.lt_succ_of_lt i.isLt⟩, htb⟩)
      · rfl
    · intro i j hij
      exact hinj _ _ (fun h => hij (Fin.ext (by simpa using congrArg Fin.val h)))
    · intro i j hij
      exact hadj _ _ (fun h => hij (Fin.ext (by simpa using congrArg Fin.val h)))

theorem peelColors_subset {n : Nat} {adj : Fin n → Fin n → Bool}
    (hsymm : ∀ u v, adj u v = adj v u)
    (active : List (Nat × Nat)) (hv : ActiveValid adj active)
    (c rem : Nat) :
    ∀ i, (peelColors active c rem).testBit i = true → rem.testBit i = true := by
  induction c generalizing rem with
  | zero => intro i hi; exact hi
  | succ c ih =>
    intro i hi
    simp only [peelColors] at hi
    split at hi
    · simp at hi
    · have h1 := ih (peelOne active rem rem) i hi
      exact (peelOne_sound hsymm active hv rem rem (fun _ h => h)).1 i h1

theorem peelColors_clique_member {n : Nat} {adj : Fin n → Fin n → Bool}
    (hsymm : ∀ u v, adj u v = adj v u)
    (active : List (Nat × Nat)) (hv : ActiveValid adj active)
    (c : Nat) :
    ∀ (rem : Nat) (f : Fin (c + 1) → Fin n),
      (∀ a, rem.testBit (f a).val = true) →
      (∀ a b, a ≠ b → f a ≠ f b) →
      (∀ a b, a ≠ b → adj (f a) (f b) = true) →
      ∃ a : Fin (c + 1), (peelColors active c rem).testBit (f a).val = true := by
  induction c with
  | zero =>
    intro rem f hmem _ _
    exact ⟨⟨0, by omega⟩, hmem ⟨0, by omega⟩⟩
  | succ c ih =>
    intro rem f hmem hinj hadj
    simp only [peelColors]
    by_cases hrem : rem = 0
    · exfalso
      have h0 := hmem ⟨0, by omega⟩
      rw [hrem] at h0; simp at h0
    · have hrem_f : (rem == 0) = false := beq_false_of_ne hrem
      simp only [hrem_f, Bool.false_eq_true, ↓reduceIte]
      have hpeel := (peelOne_sound hsymm active hv rem rem (fun _ h => h)).2.2
      by_cases hex : ∃ a0 : Fin (c + 2), (peelOne active rem rem).testBit (f a0).val = false
      · rcases hex with ⟨a0, ha0⟩
        have hmem' : ∀ i : Fin (c + 1),
            (peelOne active rem rem).testBit (f (skipIdx a0 i)).val = true := by
          intro i
          cases htb : (peelOne active rem rem).testBit (f (skipIdx a0 i)).val
          · exfalso
            have hne_idx : skipIdx a0 i ≠ a0 := skipIdx_ne a0 i
            have hne_v : f (skipIdx a0 i) ≠ f a0 := hinj _ _ hne_idx
            have hfalse := hpeel (f (skipIdx a0 i)) (f a0) (hmem _) htb (hmem _) ha0 hne_v
            have htrue := hadj _ _ hne_idx
            rw [hfalse] at htrue; cases htrue
          · rfl
        rcases ih (peelOne active rem rem) (fun i => f (skipIdx a0 i)) hmem'
            (fun i j hij => hinj _ _ (skipIdx_inj a0 hij))
            (fun i j hij => hadj _ _ (skipIdx_inj a0 hij)) with ⟨i, hi⟩
        exact ⟨skipIdx a0 i, hi⟩
      · have hmem' : ∀ i : Fin (c + 1),
            (peelOne active rem rem).testBit (f ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩).val = true := by
          intro i
          cases htb : (peelOne active rem rem).testBit (f ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩).val
          · exact False.elim (hex ⟨⟨i.val, Nat.lt_succ_of_lt i.isLt⟩, htb⟩)
          · rfl
        rcases ih (peelOne active rem rem) (fun i => f ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩) hmem'
            (fun i j hij => hinj _ _ (fun h => hij (Fin.ext (by simpa using congrArg Fin.val h))))
            (fun i j hij => hadj _ _ (fun h => hij (Fin.ext (by simpa using congrArg Fin.val h)))) with ⟨i, hi⟩
        exact ⟨⟨i.val, Nat.lt_succ_of_lt i.isLt⟩, hi⟩

theorem noClique2_sound {n : Nat} {adj : Fin n → Fin n → Bool}
    (active : List (Nat × Nat)) (hv : ActiveValid adj active)
    (cand : Nat) (hcov : ActiveCover n active cand)
    (hchk : noClique2 active cand = true) :
    ¬ IsCliqueIn adj cand 2 := by
  induction active generalizing cand with
  | nil =>
    intro ⟨f, hmem, _, _⟩
    rcases hcov (f ⟨0, by omega⟩) (hmem ⟨0, by omega⟩) with ⟨_, hm⟩
    cases hm
  | cons p rest ih =>
    rcases p with ⟨u, nb⟩
    have hv_u := hv (u, nb) (by simp)
    rcases hv_u with ⟨hu_lt, hnb⟩
    have hv_rest : ActiveValid adj rest := fun q hq => hv q (List.mem_cons_of_mem _ hq)
    simp only [noClique2] at hchk
    by_cases hcand0 : cand = 0
    · intro ⟨f, hmem, _, _⟩
      have h0 := hmem ⟨0, by omega⟩; rw [hcand0] at h0; simp at h0
    · have hc0_f : (cand == 0) = false := beq_false_of_ne hcand0
      simp only [hc0_f, Bool.false_eq_true, ↓reduceIte] at hchk
      have hbit_eq : (1 <<< u) = 2 ^ u := by rw [Nat.shiftLeft_eq, Nat.one_mul]
      by_cases hbit0 : (cand &&& (1 <<< u)) = 0
      · simp only [hbit0, beq_self_eq_true, ↓reduceIte] at hchk
        have hcu : cand.testBit u = false := by
          have := congrArg (fun z => z.testBit u) hbit0
          rw [Nat.testBit_and, hbit_eq, Nat.testBit_two_pow] at this
          simpa using this
        have hcov' : ActiveCover n rest cand := by
          intro x hx
          rcases hcov x hx with ⟨m, hm⟩
          rcases List.mem_cons.1 hm with heq | hrest
          · have hxu : x.val = u := congrArg Prod.fst heq
            rw [hxu, hcu] at hx; cases hx
          · exact ⟨m, hrest⟩
        exact ih hv_rest cand hcov' hchk
      · have hb0_f : ((cand &&& (1 <<< u)) == 0) = false := beq_false_of_ne hbit0
        simp only [hb0_f, Bool.false_eq_true, ↓reduceIte, Bool.and_eq_true, beq_iff_eq] at hchk
        rcases hchk with ⟨hdisj, hrec⟩
        let cand' := cand ^^^ (1 <<< u)
        have hcand'_tb : ∀ i, cand'.testBit i = (if i = u then !(cand.testBit i) else cand.testBit i) := by
          intro i
          simp only [cand', Nat.testBit_xor, hbit_eq, Nat.testBit_two_pow]
          by_cases hi : i = u
          · subst hi; simp
          · simp [hi, Ne.symm hi]
        have hcu : cand.testBit u = true := by
          cases htu : cand.testBit u
          · exfalso; apply hbit0
            apply Nat.eq_of_testBit_eq
            intro i
            rw [Nat.testBit_and, hbit_eq, Nat.testBit_two_pow]
            by_cases hi : u = i
            · subst hi; simp [htu]
            · simp [hi]
          · rfl
        have hcov' : ActiveCover n rest cand' := by
          intro x hx
          have hxu : x.val ≠ u := by
            intro heq
            rw [hcand'_tb, heq, hcu] at hx; simp at hx
          have hcx : cand.testBit x.val = true := by
            rw [hcand'_tb] at hx; simp [hxu] at hx; exact hx
          rcases hcov x hcx with ⟨m, hm⟩
          rcases List.mem_cons.1 hm with heq | hrest
          · exact False.elim (hxu (congrArg Prod.fst heq))
          · exact ⟨m, hrest⟩
        intro ⟨f, hmem, hinj, hadj⟩
        let i0 : Fin 2 := ⟨0, by decide⟩
        let i1 : Fin 2 := ⟨1, by decide⟩
        have h01 : i0 ≠ i1 := by decide
        by_cases h0u : (f i0).val = u
        · have h1u : (f i1).val ≠ u := fun h => hinj _ _ h01 (Fin.ext (by omega))
          have h1c' : cand'.testBit (f i1).val = true := by
            rw [hcand'_tb]; simp only [h1u, ↓reduceIte]; exact hmem i1
          have h1nb : nb.testBit (f i1).val = true := by
            rw [hnb (f i1)]
            have hf0 : (⟨u, hu_lt⟩ : Fin n) = f i0 := Fin.ext h0u.symm
            rw [hf0]; exact hadj _ _ h01
          have hzero := congrArg (fun z => z.testBit (f i1).val) hdisj
          rw [Nat.testBit_and, h1c', h1nb] at hzero
          simp at hzero
        · by_cases h1u : (f i1).val = u
          · have h0c' : cand'.testBit (f i0).val = true := by
              rw [hcand'_tb]; simp only [h0u, ↓reduceIte]; exact hmem i0
            have h0nb : nb.testBit (f i0).val = true := by
              rw [hnb (f i0)]
              have hf1 : (⟨u, hu_lt⟩ : Fin n) = f i1 := Fin.ext h1u.symm
              rw [hf1]; exact hadj _ _ (Ne.symm h01)
            have hzero := congrArg (fun z => z.testBit (f i0).val) hdisj
            rw [Nat.testBit_and, h0c', h0nb] at hzero
            simp at hzero
          · apply ih hv_rest cand' hcov' hrec
            refine ⟨f, ?_, hinj, hadj⟩
            intro a
            rcases a with ⟨av, ah⟩
            cases av with
            | zero =>
              have ha0 : (⟨0, ah⟩ : Fin 2) = i0 := rfl
              rw [ha0, hcand'_tb]; simp only [h0u, ↓reduceIte]; exact hmem i0
            | succ av =>
              cases av with
              | zero =>
                have ha1 : (⟨1, ah⟩ : Fin 2) = i1 := rfl
                rw [ha1, hcand'_tb]; simp only [h1u, ↓reduceIte]; exact hmem i1
              | succ _ => omega

theorem noCliqueBranch_sound {n : Nat} {adj : Fin n → Fin n → Bool}
    (k : Nat) (recCheck : Nat → Bool)
    (active : List (Nat × Nat)) (hv : ActiveValid adj active)
    (r c : Nat)
    (hrsub : ∀ i, r.testBit i = true → c.testBit i = true)
    (hrec_ok : ∀ csub, (∀ i, csub.testBit i = true → c.testBit i = true) →
      recCheck csub = true → ¬ IsCliqueIn adj csub k)
    (hcov : ActiveCover n active r)
    (hchk : noCliqueBranch recCheck active r c = true) :
    ¬ (∃ f : Fin (k + 1) → Fin n,
        (∀ a : Fin (k + 1), c.testBit (f a).val = true) ∧
        (∀ a b : Fin (k + 1), a ≠ b → f a ≠ f b) ∧
        (∀ a b : Fin (k + 1), a ≠ b → adj (f a) (f b) = true) ∧
        (∃ a : Fin (k + 1), r.testBit (f a).val = true)) := by
  induction active generalizing r c with
  | nil =>
    intro ⟨f, _, _, _, ⟨a, ha⟩⟩
    rcases hcov (f a) ha with ⟨_, hm⟩
    cases hm
  | cons p rest ih =>
    rcases p with ⟨u, nb⟩
    have hv_u := hv (u, nb) (by simp)
    rcases hv_u with ⟨hu_lt, hnb⟩
    have hv_rest : ActiveValid adj rest := fun q hq => hv q (List.mem_cons_of_mem _ hq)
    simp only [noCliqueBranch] at hchk
    by_cases hr0 : r = 0
    · intro ⟨f, _, _, _, ⟨a, ha⟩⟩
      rw [hr0] at ha; simp at ha
    · have hr0_f : (r == 0) = false := beq_false_of_ne hr0
      simp only [hr0_f, Bool.false_eq_true, ↓reduceIte] at hchk
      have hbit_eq : (1 <<< u) = 2 ^ u := by rw [Nat.shiftLeft_eq, Nat.one_mul]
      by_cases hbit0 : (r &&& (1 <<< u)) = 0
      · simp only [hbit0, beq_self_eq_true, ↓reduceIte] at hchk
        have hru : r.testBit u = false := by
          have := congrArg (fun z => z.testBit u) hbit0
          rw [Nat.testBit_and, hbit_eq, Nat.testBit_two_pow] at this
          simpa using this
        have hcov' : ActiveCover n rest r := by
          intro x hx
          rcases hcov x hx with ⟨m, hm⟩
          rcases List.mem_cons.1 hm with heq | hrest
          · have hxu : x.val = u := congrArg Prod.fst heq
            rw [hxu, hru] at hx; cases hx
          · exact ⟨m, hrest⟩
        exact ih hv_rest r c hrsub hrec_ok hcov' hchk
      · have hb0_f : ((r &&& (1 <<< u)) == 0) = false := beq_false_of_ne hbit0
        simp only [hb0_f, Bool.false_eq_true, ↓reduceIte, Bool.and_eq_true] at hchk
        rcases hchk with ⟨hsub_ok, htail_ok⟩
        let c' := c ^^^ (1 <<< u)
        let r' := r ^^^ (1 <<< u)
        have hru : r.testBit u = true := by
          cases htu : r.testBit u
          · exfalso; apply hbit0
            apply Nat.eq_of_testBit_eq
            intro i
            rw [Nat.testBit_and, hbit_eq, Nat.testBit_two_pow]
            by_cases hi : u = i
            · subst hi; simp [htu]
            · simp [hi]
          · rfl
        have hcu : c.testBit u = true := hrsub u hru
        have hc'_tb : ∀ i, c'.testBit i = (if i = u then !(c.testBit i) else c.testBit i) := by
          intro i
          simp only [c', Nat.testBit_xor, hbit_eq, Nat.testBit_two_pow]
          by_cases hi : i = u
          · subst hi; simp
          · simp [hi, Ne.symm hi]
        have hr'_tb : ∀ i, r'.testBit i = (if i = u then !(r.testBit i) else r.testBit i) := by
          intro i
          simp only [r', Nat.testBit_xor, hbit_eq, Nat.testBit_two_pow]
          by_cases hi : i = u
          · subst hi; simp
          · simp [hi, Ne.symm hi]
        have hc'_sub_c : ∀ i, c'.testBit i = true → c.testBit i = true := by
          intro i hi
          rw [hc'_tb] at hi
          by_cases hiu : i = u
          · subst hiu; rw [hcu] at hi; simp at hi
          · simp [hiu] at hi; exact hi
        have hr'_sub_c' : ∀ i, r'.testBit i = true → c'.testBit i = true := by
          intro i hi
          rw [hr'_tb] at hi
          by_cases hiu : i = u
          · subst hiu; rw [hru] at hi; simp at hi
          · simp [hiu] at hi
            rw [hc'_tb]; simp [hiu, hrsub i hi]
        have hcov' : ActiveCover n rest r' := by
          intro x hx
          have hxu : x.val ≠ u := by
            intro heq; rw [hr'_tb, heq, hru] at hx; simp at hx
          have hrx : r.testBit x.val = true := by
            rw [hr'_tb] at hx; simp [hxu] at hx; exact hx
          rcases hcov x hrx with ⟨m, hm⟩
          rcases List.mem_cons.1 hm with heq | hrest
          · exact False.elim (hxu (congrArg Prod.fst heq))
          · exact ⟨m, hrest⟩
        intro ⟨f, hmem, hinj, hadj, ⟨a_hit, ha_hit⟩⟩
        by_cases hhit_u : ∃ a0 : Fin (k + 1), (f a0).val = u
        · rcases hhit_u with ⟨a0, ha0⟩
          have hc'sub : ∀ i, (c' &&& nb).testBit i = true → c.testBit i = true := by
            intro i hi
            rw [Nat.testBit_and] at hi
            simp only [Bool.and_eq_true] at hi
            exact hc'_sub_c i hi.1
          apply hrec_ok (c' &&& nb) hc'sub hsub_ok
          refine ⟨fun i => f (skipIdx a0 i), ?_, ?_, ?_⟩
          · intro i
            rw [Nat.testBit_and]
            have hne_idx : skipIdx a0 i ≠ a0 := skipIdx_ne a0 i
            have hne_v : (f (skipIdx a0 i)).val ≠ u := by
              intro h; apply hinj _ _ hne_idx; exact Fin.ext (by omega)
            have hcm : c'.testBit (f (skipIdx a0 i)).val = true := by
              rw [hc'_tb]; simp [hne_v, hmem _]
            have hnbm : nb.testBit (f (skipIdx a0 i)).val = true := by
              rw [hnb (f (skipIdx a0 i))]
              have hfa0 : (⟨u, hu_lt⟩ : Fin n) = f a0 := Fin.ext ha0.symm
              rw [hfa0]; exact hadj _ _ (Ne.symm hne_idx)
            simp [hcm, hnbm]
          · intro i j hij
            exact hinj _ _ (skipIdx_inj a0 hij)
          · intro i j hij
            exact hadj _ _ (skipIdx_inj a0 hij)
        · apply ih hv_rest r' c' hr'_sub_c'
            (fun csub hcsub => hrec_ok csub (fun i hi => hc'_sub_c i (hcsub i hi)))
            hcov' htail_ok
          refine ⟨f, ?_, hinj, hadj, ?_⟩
          · intro a
            have hne_u : (f a).val ≠ u := fun h => hhit_u ⟨a, h⟩
            rw [hc'_tb]; simp [hne_u, hmem a]
          · refine ⟨a_hit, ?_⟩
            have hne_u : (f a_hit).val ≠ u := fun h => hhit_u ⟨a_hit, h⟩
            rw [hr'_tb]; simp [hne_u, ha_hit]

theorem noClique_sound {n : Nat} {adj : Fin n → Fin n → Bool}
    (hsymm : ∀ u v, adj u v = adj v u)
    (k : Nat) :
    ∀ (active : List (Nat × Nat)) (cand : Nat),
      ActiveValid adj active →
      ActiveCover n active cand →
      noClique active k cand = true →
      ¬ IsCliqueIn adj cand k := by
  induction k with
  | zero =>
    intro active cand _ _ hchk
    simp [noClique] at hchk
  | succ k ih =>
    intro active cand hv hcov hchk
    cases k with
    | zero =>
      have hcand0 : cand = 0 := by simpa [noClique] using hchk
      intro ⟨f, hmem, _, _⟩
      have h0 := hmem ⟨0, by omega⟩; rw [hcand0, Nat.zero_testBit] at h0; cases h0
    | succ k' =>
      cases k' with
      | zero =>
        exact noClique2_sound active hv cand hcov hchk
      | succ k'' =>
        simp only [noClique] at hchk
        by_cases hc0 : cand = 0
        · intro ⟨f, hmem, _, _⟩
          have h0 := hmem ⟨0, by omega⟩; rw [hc0, Nat.zero_testBit] at h0; cases h0
        · have hc0_f : (cand == 0) = false := beq_false_of_ne hc0
          simp only [hc0_f, Bool.false_eq_true, ↓reduceIte] at hchk
          let act := filterActive cand active
          have hv_act : ActiveValid adj act := filterActive_valid cand active hv
          have hcov_act : ActiveCover n act cand := filterActive_cover cand active hcov
          let rem := peelColors act (k'' + 2) cand
          have hrem_sub : ∀ i, rem.testBit i = true → cand.testBit i = true :=
            peelColors_subset hsymm act hv_act (k'' + 2) cand
          have hcov_rem : ActiveCover n act rem := fun u hu => hcov_act u (hrem_sub u.val hu)
          by_cases hrem0 : rem = 0
          · intro ⟨f, hmem, hinj, hadj⟩
            rcases peelColors_clique_member hsymm act hv_act (k'' + 2) cand f hmem hinj hadj with ⟨a, ha⟩
            change rem.testBit (f a).val = true at ha
            rw [hrem0, Nat.zero_testBit] at ha; cases ha
          · have hrem0_f : (peelColors act (k'' + 2) cand == 0) = false := beq_false_of_ne hrem0
            dsimp only [act] at hrem0_f
            simp only [hrem0_f, Bool.false_eq_true, ↓reduceIte] at hchk
            intro ⟨f, hmem, hinj, hadj⟩
            have hhit : ∃ a : Fin (k'' + 3), rem.testBit (f a).val = true :=
              peelColors_clique_member hsymm act hv_act (k'' + 2) cand f hmem hinj hadj
            exact noCliqueBranch_sound (k'' + 2) (noClique act (k'' + 2))
              act hv_act rem cand hrem_sub
              (fun csub hcsub hsub => ih act csub hv_act (fun u hu => hcov_act u (hcsub u.val hu)) hsub)
              hcov_rem hchk ⟨f, hmem, hinj, hadj, hhit⟩

/-! ### C4-freeness and edge count soundness -/

/-- If `m &&& (m - 1) = 0`, at most one bit of `m` is `1`. -/
theorem eq_of_and_pred_eq_zero (m : Nat) (h : (m &&& (m - 1)) = 0) :
    ∀ i j : Nat, m.testBit i = true → m.testBit j = true → i = j := by
  induction m using Nat.strongRecOn with
  | ind m ih =>
    cases m with
    | zero => intro i _ hi; simp at hi
    | succ m' =>
      by_cases hodd : (m' + 1) % 2 = 1
      · have hprev : (m' + 1) - 1 = m' := by omega
        rw [hprev] at h
        have hzero : m' = 0 := by
          apply Nat.eq_of_testBit_eq
          intro k
          have hk := congrArg (fun z => z.testBit k) h
          rw [Nat.testBit_and] at hk
          cases k with
          | zero =>
            rw [Nat.testBit_zero]
            have : m' % 2 = 0 := by omega
            simp [this]
          | succ k =>
            have hsame : (m' + 1).testBit (k + 1) = m'.testBit (k + 1) := by
              rw [Nat.testBit_succ, Nat.testBit_succ]
              have : (m' + 1) / 2 = m' / 2 := by omega
              rw [this]
            rw [hsame] at hk
            cases hmt : m'.testBit (k + 1) <;> simp [hmt] at hk ⊢
        subst hzero
        intro i j hi hj
        cases i with
        | zero =>
          cases j with
          | zero => rfl
          | succ j => simp [Nat.testBit_succ] at hj
        | succ i => simp [Nat.testBit_succ] at hi
      · have heven : (m' + 1) % 2 = 0 := by omega
        let q := (m' + 1) / 2
        have hq_pos : 0 < q := by omega
        have hq_lt : q < m' + 1 := by omega
        have hq_and : (q &&& (q - 1)) = 0 := by
          apply Nat.eq_of_testBit_eq
          intro k
          have hk := congrArg (fun z => z.testBit (k + 1)) h
          rw [Nat.testBit_and, Nat.testBit_succ, Nat.testBit_succ] at hk
          have h1 : (m' + 1) / 2 = q := rfl
          have h2 : ((m' + 1) - 1) / 2 = q - 1 := by omega
          rw [h1, h2] at hk
          simpa [Nat.testBit_and] using hk
        intro i j hi hj
        cases i with
        | zero => rw [Nat.testBit_zero] at hi; simp [heven] at hi
        | succ i =>
          cases j with
          | zero => rw [Nat.testBit_zero] at hj; simp [heven] at hj
          | succ j =>
            rw [Nat.testBit_succ] at hi hj
            exact congrArg Nat.succ (ih q hq_lt hq_and i j hi hj)

theorem c4FreeRow_sound (a : Nat) (bs : List Nat) (h : c4FreeRow a bs = true) :
    ∀ k, k < bs.length → ((a &&& getRow bs k) &&& ((a &&& getRow bs k) - 1)) = 0 := by
  induction bs with
  | nil => intro k hk; cases hk
  | cons b rest ih =>
    simp only [c4FreeRow, Bool.and_eq_true, beq_iff_eq] at h
    intro k hk
    cases k with
    | zero => exact h.1
    | succ k => exact ih h.2 k (Nat.lt_of_succ_lt_succ hk)

theorem checkC4Free_sound_pairs (rows : List Nat) (h : checkC4Free rows = true) :
    ∀ i j, i < j → j < rows.length →
      ((getRow rows i &&& getRow rows j) &&& ((getRow rows i &&& getRow rows j) - 1)) = 0 := by
  induction rows with
  | nil => intro i j _ hj; cases hj
  | cons a rest ih =>
    simp only [checkC4Free, Bool.and_eq_true] at h
    intro i j hij hj
    cases i with
    | zero =>
      cases j with
      | zero => omega
      | succ j => exact c4FreeRow_sound a rest h.1 j (Nat.lt_of_succ_lt_succ hj)
    | succ i =>
      cases j with
      | zero => omega
      | succ j => exact ih h.2 i j (Nat.lt_of_succ_lt_succ hij) (Nat.lt_of_succ_lt_succ hj)

theorem checkC4Free_sound (n : Nat) (rows : List Nat) (hlen : rows.length = n)
    (hsymm : ∀ u v : Fin n, rowsAdj n rows u v = rowsAdj n rows v u)
    (hc4 : checkC4Free rows = true) :
    ¬ HasC4 (rowsAdj n rows) := by
  intro ⟨a, b, c, d, hab, hac, had, hbc, hbd, hcd, eab, ebc, ecd, eda⟩
  have hpairs := checkC4Free_sound_pairs rows hc4
  have hcb : rowsAdj n rows c b = true := by rw [hsymm]; exact ebc
  have had_e : rowsAdj n rows a d = true := by rw [hsymm]; exact eda
  have hne_ac : a.val ≠ c.val := fun h => hac (Fin.ext h)
  have hne_bd : b.val ≠ d.val := fun h => hbd (Fin.ext h)
  by_cases hlt : a.val < c.val
  · have hzero := hpairs a.val c.val hlt (by rw [hlen]; exact c.isLt)
    have hb_tb : (getRow rows a.val &&& getRow rows c.val).testBit b.val = true := by
      rw [Nat.testBit_and]; exact Bool.and_eq_true_iff.2 ⟨eab, hcb⟩
    have hd_tb : (getRow rows a.val &&& getRow rows c.val).testBit d.val = true := by
      rw [Nat.testBit_and]; exact Bool.and_eq_true_iff.2 ⟨had_e, ecd⟩
    exact hne_bd (eq_of_and_pred_eq_zero _ hzero b.val d.val hb_tb hd_tb)
  · have hgt : c.val < a.val := by omega
    have hzero := hpairs c.val a.val hgt (by rw [hlen]; exact a.isLt)
    have hb_tb : (getRow rows c.val &&& getRow rows a.val).testBit b.val = true := by
      rw [Nat.testBit_and]; exact Bool.and_eq_true_iff.2 ⟨hcb, eab⟩
    have hd_tb : (getRow rows c.val &&& getRow rows a.val).testBit d.val = true := by
      rw [Nat.testBit_and]; exact Bool.and_eq_true_iff.2 ⟨ecd, had_e⟩
    exact hne_bd (eq_of_and_pred_eq_zero _ hzero b.val d.val hb_tb hd_tb)

theorem countRowUpperBits_eq (n : Nat) (rows : List Nat) (u : Fin n) (hi : Nat) (hhi : hi ≤ n) :
    countRowUpperBits (getRow rows u.val) u.val hi =
      rowUpperEdges (rowsAdj n rows) u hi hhi := by
  induction hi with
  | zero => rfl
  | succ k ih =>
    rw [countRowUpperBits, rowUpperEdges, ih (Nat.le_of_succ_le hhi)]
    rfl

theorem countEdgesAux_eq (n : Nat) (rows : List Nat) (rs : List Nat) (u0 : Nat)
    (hlen : u0 + rs.length = n)
    (hmatch : ∀ k, k < rs.length → getRow rs k = getRow rows (u0 + k)) :
    edgeCountAux (rowsAdj n rows) u0 (by omega) + countEdgesAux n rs u0 =
      edgeCountAux (rowsAdj n rows) n (Nat.le_refl n) := by
  induction rs generalizing u0 with
  | nil =>
    have hu : u0 = n := by simp at hlen; omega
    subst hu
    simp [countEdgesAux]
  | cons r rest ih =>
    simp only [countEdgesAux]
    have hlt : u0 < n := by simp at hlen; omega
    have hlen' : (u0 + 1) + rest.length = n := by simp at hlen; omega
    have hr : r = getRow rows u0 := by
      have := hmatch 0 (by simp)
      simpa [getRow] using this
    have hstep : countRowUpperBits r u0 n =
        rowUpperEdges (rowsAdj n rows) ⟨u0, hlt⟩ n (Nat.le_refl n) := by
      rw [hr]
      exact countRowUpperBits_eq n rows ⟨u0, hlt⟩ n (Nat.le_refl n)
    have hrec := ih (u0 + 1) hlen' (fun k hk => by
      have := hmatch (k + 1) (Nat.succ_lt_succ hk)
      have heq : u0 + (k + 1) = u0 + 1 + k := by omega
      rw [heq] at this
      exact this)
    have hedge : edgeCountAux (rowsAdj n rows) (u0 + 1) (by omega) =
        edgeCountAux (rowsAdj n rows) u0 (by omega) +
        rowUpperEdges (rowsAdj n rows) ⟨u0, hlt⟩ n (Nat.le_refl n) := rfl
    rw [hstep]
    omega

theorem countEdges_eq (n : Nat) (rows : List Nat) (hlen : rows.length = n) :
    countEdges n rows = edgeCount (rowsAdj n rows) := by
  unfold countEdges edgeCount
  have h := countEdgesAux_eq n rows rows 0 (by omega) (fun k _ => by simp)
  simp only [edgeCountAux, Nat.zero_add] at h
  exact h

/-! ## Top-level soundness theorems -/

/-- **End-to-end soundness for Ramsey witness graphs**: if `rows` passes `checkSimpleGraph`,
has no `s`-clique, and its complement `compRows n rows` has no `t`-clique, then
`ValidRamseyGraph s t n` (certifying `R(s, t) ≥ n + 1`). -/
theorem validRamseyGraph_of_check (s t n : Nat) (rows : List Nat)
    (hsg : checkSimpleGraph n rows = true)
    (hs : checkNoClique n s rows = true)
    (ht : checkNoClique n t (compRows n rows) = true) :
    ValidRamseyGraph s t n := by
  have hc := simpleGraph_of_check n rows hsg
  rcases hc with ⟨hlen, _, hloop, hsymm⟩
  let G : SimpleGraph n := { adj := rowsAdj n rows, symm := hsymm, loopless := hloop }
  refine ⟨G, ?_, ?_⟩
  · -- No s-clique in G
    have hv : ActiveValid G.adj (toActive rows 0) :=
      toActive_valid G.adj rows 0 (fun k hk => ⟨by omega, fun v => by simp [G, rowsAdj]⟩)
    have hcov : ActiveCover n (toActive rows 0) ((1 <<< n) - 1) :=
      fun u _ => toActive_cover n rows 0 (by omega) u (Nat.zero_le _)
    have hno := noClique_sound hsymm s (toActive rows 0) ((1 <<< n) - 1) hv hcov hs
    intro ⟨f, hinj, hadj⟩
    apply hno
    refine ⟨f, ?_, hinj, hadj⟩
    intro a
    have hpow : (1 <<< n) = 2 ^ n := by rw [Nat.shiftLeft_eq, Nat.one_mul]
    rw [hpow, Nat.testBit_two_pow_sub_one]
    exact decide_eq_true (f a).isLt
  · -- No t-independent set in G (equivalently no t-clique in complement graph)
    let cadj : Fin n → Fin n → Bool := fun u v => (u.val != v.val) && !(G.adj u v)
    have hcsymm : ∀ u v : Fin n, cadj u v = cadj v u := by
      intro u v
      simp only [cadj]
      by_cases huv : u.val = v.val
      · have heq : u = v := Fin.ext huv; subst heq; rfl
      · have h1 : (u.val != v.val) = true := bne_iff_ne.2 huv
        have h2 : (v.val != u.val) = true := bne_iff_ne.2 (Ne.symm huv)
        rw [h1, h2, G.symm u v]
    have hclen : (compRows n rows).length = n := by rw [compRows_length, hlen]
    have hv : ActiveValid cadj (toActive (compRows n rows) 0) :=
      toActive_valid cadj (compRows n rows) 0 (fun k hk =>
        ⟨by omega, fun v => by
          have hk' : k < n := by omega
          have heq : (⟨0 + k, by omega⟩ : Fin n) = ⟨k, hk'⟩ := Fin.ext (Nat.zero_add k)
          rw [heq]
          exact compRows_testBit n rows hlen hloop ⟨k, hk'⟩ v⟩)
    have hcov : ActiveCover n (toActive (compRows n rows) 0) ((1 <<< n) - 1) :=
      fun u _ => toActive_cover n (compRows n rows) 0 (by omega) u (Nat.zero_le _)
    have hno := noClique_sound hcsymm t (toActive (compRows n rows) 0) ((1 <<< n) - 1) hv hcov ht
    intro ⟨f, hinj, hind⟩
    apply hno
    refine ⟨f, ?_, hinj, ?_⟩
    · intro a
      have hpow : (1 <<< n) = 2 ^ n := by rw [Nat.shiftLeft_eq, Nat.one_mul]
      rw [hpow, Nat.testBit_two_pow_sub_one]
      exact decide_eq_true (f a).isLt
    · intro a b hab
      have hne : (f a).val ≠ (f b).val := fun h => hinj a b hab (Fin.ext h)
      have hne_b : ((f a).val != (f b).val) = true := bne_iff_ne.2 hne
      simp [cadj, hne_b, hind a b hab]

/-- **End-to-end soundness for C4-free extremal graphs**: if `rows` passes `checkSimpleGraph`,
has `countEdges n rows = e`, and passes `checkC4Free`, then `ValidC4FreeGraph n e`
(certifying `ex(n, C_4) ≥ e`). -/
theorem validC4FreeGraph_of_check (n e : Nat) (rows : List Nat)
    (hsg : checkSimpleGraph n rows = true)
    (he : countEdges n rows = e)
    (hc4 : checkC4Free rows = true) :
    ValidC4FreeGraph n e := by
  have hc := simpleGraph_of_check n rows hsg
  rcases hc with ⟨hlen, _, hloop, hsymm⟩
  refine ⟨{ adj := rowsAdj n rows, symm := hsymm, loopless := hloop }, ?_, ?_⟩
  · rw [← countEdges_eq n rows hlen]; exact he
  · exact checkC4Free_sound n rows hlen hsymm hc4

end ExtremalGraphs
