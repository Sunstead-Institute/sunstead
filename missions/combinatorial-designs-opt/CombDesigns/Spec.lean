/-!
# Combinatorial Designs: Covering Arrays CAN(t, k, v) & Optimal Golomb Rulers G(k)

This module formalizes two classical combinatorial design minimization frontiers in pure
Lean 4.36.0 (zero Mathlib, standard axioms only):

1. **Covering Arrays `CA(N; t, k, v)` (`ValidCoveringArray2 k v N`, `ValidCoveringArray3 k v N`)**:
   an `N × k` array over alphabet `Fin v` in which every `t`-tuple of distinct columns
   covers all `v^t` value tuples at least once, certifying `CAN(t, k, v) ≤ N`.
   Verified via a fast bit-sliced column-mask evaluator (`checkCA2`, `checkCA3`) that checks
   all `N` rows simultaneously per symbol tuple using bitwise `&&&`, proved completely sound
   in `validCoveringArray2_of_check` and `validCoveringArray3_of_check`.
2. **Optimal Golomb Rulers `G(k)` (`ValidGolombRuler k L`)**: a strictly increasing sequence
   of `k` integer marks in `{0, ..., L}` whose `C(k, 2)` pairwise positive differences are
   all distinct, certifying `G(k) ≤ L`. Verified via a pairwise difference bitmask
   (`checkGolombRuler`) with complete soundness proof (`validGolombRuler_of_check`).

Upstream covering-array optimization benchmarks are pinned to `huayaow/DPSO` (Wu, Nie, Kuo,
Leung & Colbourn, *IEEE Trans. Evol. Comput.* 2015) at commit
`e28d4f2c4e2f989e5d9ff5f78c5214a3331fe2dc` (MIT).
-/

namespace CombDesigns

/-! ## Mission target predicates -/

/-- Existence of a strength-2 covering array `CA(N; 2, k, v)` (certifying `CAN(2, k, v) ≤ N`):
every pair of distinct columns covers all `v^2` symbol pairs. -/
def ValidCoveringArray2 (k v N : Nat) : Prop :=
  ∃ A : Fin N → Fin k → Fin v,
    ∀ c₁ c₂ : Fin k, c₁ ≠ c₂ →
      ∀ s₁ s₂ : Fin v, ∃ r : Fin N, A r c₁ = s₁ ∧ A r c₂ = s₂

/-- Existence of a strength-3 covering array `CA(N; 3, k, v)` (certifying `CAN(3, k, v) ≤ N`):
every triple of distinct columns covers all `v^3` symbol triples. -/
def ValidCoveringArray3 (k v N : Nat) : Prop :=
  ∃ A : Fin N → Fin k → Fin v,
    ∀ c₁ c₂ c₃ : Fin k, c₁ ≠ c₂ → c₁ ≠ c₃ → c₂ ≠ c₃ →
      ∀ s₁ s₂ s₃ : Fin v, ∃ r : Fin N, A r c₁ = s₁ ∧ A r c₂ = s₂ ∧ A r c₃ = s₃

/-- Existence of a `k`-mark Golomb ruler of length at most `L` (certifying `G(k) ≤ L`):
`k` strictly increasing marks in `{0, ..., L}` with all `C(k, 2)` pairwise positive
differences distinct. -/
def ValidGolombRuler (k L : Nat) : Prop :=
  ∃ marks : List Nat,
    marks.length = k ∧
    (∀ i : Fin marks.length, marks.get i ≤ L) ∧
    (∀ i j : Fin marks.length, i.val < j.val → marks.get i < marks.get j) ∧
    (∀ i₁ j₁ i₂ j₂ : Fin marks.length,
      i₁.val < j₁.val → i₂.val < j₂.val →
      marks.get j₁ - marks.get i₁ = marks.get j₂ - marks.get i₂ →
      i₁ = i₂ ∧ j₁ = j₂)

/-! ## 1. Bit-sliced Covering Array kernel evaluator -/

def getNat : List Nat → Nat → Nat
  | [], _ => 0
  | x :: _, 0 => x
  | _ :: xs, i + 1 => getNat xs i

def getRowList : List (List Nat) → Nat → List Nat
  | [], _ => []
  | r :: _, 0 => r
  | _ :: rs, i + 1 => getRowList rs i

/-- Check that every entry in a row is `< v`. -/
def checkRowEntries (v : Nat) : List Nat → Bool
  | [] => true
  | x :: xs => Nat.blt x v && checkRowEntries v xs

/-- Check that `rows` is a well-formed `N × k` matrix over `{0, ..., v - 1}`. -/
def checkMatrixRows (k v : Nat) : List (List Nat) → Bool
  | [] => true
  | r :: rs => (r.length == k) && checkRowEntries v r && checkMatrixRows k v rs

def checkMatrix (N k v : Nat) (rows : List (List Nat)) : Bool :=
  (rows.length == N) && checkMatrixRows k v rows

/-- Build the `N`-bit mask of rows `r` where `rows[r][c] == s`. -/
def buildSymMaskAux (c s : Nat) : List (List Nat) → Nat → Nat
  | [], _ => 0
  | r :: rs, idx =>
    let rest := buildSymMaskAux c s rs (idx + 1)
    if getNat r c == s then rest ||| (1 <<< idx) else rest

def buildSymMask (rows : List (List Nat)) (c s : Nat) : Nat :=
  buildSymMaskAux c s rows 0

/-- Build the list `[mask(c, 0), ..., mask(c, v - 1)]` for column `c`. -/
def buildColSymMasksAux (rows : List (List Nat)) (c : Nat) : Nat → Nat → List Nat
  | 0, _ => []
  | rem + 1, s => buildSymMask rows c s :: buildColSymMasksAux rows c rem (s + 1)

def buildColSymMasks (rows : List (List Nat)) (v c : Nat) : List Nat :=
  buildColSymMasksAux rows c v 0

/-- Build column-sliced bitmasks for all `k` columns. -/
def buildAllColsAux (rows : List (List Nat)) (v : Nat) : Nat → Nat → List (List Nat)
  | 0, _ => []
  | rem + 1, c => buildColSymMasks rows v c :: buildAllColsAux rows v rem (c + 1)

def buildAllCols (rows : List (List Nat)) (k v : Nat) : List (List Nat) :=
  buildAllColsAux rows v k 0

/-- Check `(a &&& b) != 0` for all `b ∈ ms`. -/
def checkAndNonZeroList (a : Nat) : List Nat → Bool
  | [] => true
  | b :: bs => ((a &&& b) != 0) && checkAndNonZeroList a bs

/-- Check `(a &&& b) != 0` for all `a ∈ m1, b ∈ m2`. -/
def checkPairMasks : List Nat → List Nat → Bool
  | [], _ => true
  | a :: as, m2 => checkAndNonZeroList a m2 && checkPairMasks as m2

/-- Check strength-2 coverage for `c1` against all later columns. -/
def checkCol2 (m1 : List Nat) : List (List Nat) → Bool
  | [] => true
  | m2 :: rest => checkPairMasks m1 m2 && checkCol2 m1 rest

def checkAllCols2 : List (List Nat) → Bool
  | [] => true
  | m1 :: rest => checkCol2 m1 rest && checkAllCols2 rest

def checkCA2 (N k v : Nat) (rows : List (List Nat)) : Bool :=
  checkMatrix N k v rows && checkAllCols2 (buildAllCols rows k v)

/-- Check `(ab &&& c) != 0` for every `ab ∈ pairMasks` and every `c ∈ m3`. -/
def checkTripleAgainstCol (pairMasks m3 : List Nat) : Bool :=
  checkPairMasks pairMasks m3

def checkPairAgainstRest (pairMasks : List Nat) : List (List Nat) → Bool
  | [] => true
  | m3 :: rest => checkTripleAgainstCol pairMasks m3 && checkPairAgainstRest pairMasks rest

/-- Compute all pairwise intersections `a &&& b` for `a ∈ m1, b ∈ m2`. -/
def intersectLists : List Nat → List Nat → List Nat
  | [], _ => []
  | a :: as, m2 => m2.map (fun b => a &&& b) ++ intersectLists as m2

def checkCol3 (m1 : List Nat) : List (List Nat) → Bool
  | [] => true
  | m2 :: rest =>
    checkPairAgainstRest (intersectLists m1 m2) rest && checkCol3 m1 rest

def checkAllCols3 : List (List Nat) → Bool
  | [] => true
  | m1 :: rest => checkCol3 m1 rest && checkAllCols3 rest

def checkCA3 (N k v : Nat) (rows : List (List Nat)) : Bool :=
  checkMatrix N k v rows && checkAllCols3 (buildAllCols rows k v)

/-! ## Soundness proofs for Covering Arrays -/

theorem exists_testBit_of_ne_zero (x : Nat) (hx : x ≠ 0) :
    ∃ r : Nat, x.testBit r = true := by
  induction x using Nat.strongRecOn with
  | ind x ih =>
    by_cases hodd : x % 2 = 1
    · exact ⟨0, by rw [Nat.testBit_zero]; simp [hodd]⟩
    · have hq_pos : 0 < x / 2 := by omega
      have hq_lt : x / 2 < x := by omega
      rcases ih (x / 2) hq_lt (by omega) with ⟨r', hr'⟩
      exact ⟨r' + 1, by rw [Nat.testBit_succ]; exact hr'⟩

theorem checkRowEntries_sound (v : Nat) (row : List Nat) (h : checkRowEntries v row = true) :
    ∀ c, c < row.length → getNat row c < v := by
  induction row with
  | nil => intro c hc; cases hc
  | cons x xs ih =>
    simp only [checkRowEntries, Bool.and_eq_true, Nat.blt_eq] at h
    intro c hc
    cases c with
    | zero => exact h.1
    | succ c => exact ih h.2 c (Nat.lt_of_succ_lt_succ hc)

theorem checkMatrixRows_sound (k v : Nat) (rows : List (List Nat))
    (h : checkMatrixRows k v rows = true) :
    ∀ r, r < rows.length →
      (getRowList rows r).length = k ∧
      ∀ c, c < k → getNat (getRowList rows r) c < v := by
  induction rows with
  | nil => intro r hr; cases hr
  | cons row rs ih =>
    simp only [checkMatrixRows, Bool.and_eq_true, beq_iff_eq] at h
    intro r hr
    cases r with
    | zero =>
      refine ⟨h.1.1, fun c hc => checkRowEntries_sound v row h.1.2 c (by rw [h.1.1]; exact hc)⟩
    | succ r =>
      exact ih h.2 r (Nat.lt_of_succ_lt_succ hr)

theorem buildSymMaskAux_testBit (c s : Nat) (rows : List (List Nat)) (idx0 r : Nat) :
    (buildSymMaskAux c s rows idx0).testBit r = true →
      idx0 ≤ r ∧ r < idx0 + rows.length ∧ getNat (getRowList rows (r - idx0)) c = s := by
  induction rows generalizing idx0 with
  | nil => intro h; simp [buildSymMaskAux] at h
  | cons row rs ih =>
    intro h
    simp only [buildSymMaskAux] at h
    split at h
    · next heq =>
      rw [Nat.testBit_or] at h
      have hbit : (1 <<< idx0) = 2 ^ idx0 := by rw [Nat.shiftLeft_eq, Nat.one_mul]
      rw [hbit, Nat.testBit_two_pow] at h
      rcases Bool.or_eq_true_iff.1 h with hrest | hself
      · rcases ih (idx0 + 1) hrest with ⟨hlo, hhi, hval⟩
        have hsub : r - idx0 = (r - (idx0 + 1)) + 1 := by omega
        rw [hsub]
        refine ⟨by omega, by simp; omega, ?_⟩
        simpa [getRowList] using hval
      · have hreq : idx0 = r := of_decide_eq_true hself
        subst hreq
        refine ⟨Nat.le_refl _, by simp, ?_⟩
        have hzero : idx0 - idx0 = 0 := by omega
        rw [hzero]
        exact beq_iff_eq.1 heq
    · rcases ih (idx0 + 1) h with ⟨hlo, hhi, hval⟩
      have hsub : r - idx0 = (r - (idx0 + 1)) + 1 := by omega
      rw [hsub]
      refine ⟨by omega, by simp; omega, ?_⟩
      simpa [getRowList] using hval

theorem buildSymMask_testBit (rows : List (List Nat)) (c s r : Nat)
    (h : (buildSymMask rows c s).testBit r = true) :
    r < rows.length ∧ getNat (getRowList rows r) c = s := by
  rcases buildSymMaskAux_testBit c s rows 0 r h with ⟨_, hhi, hval⟩
  exact ⟨by omega, by simpa using hval⟩

theorem get_buildColSymMasksAux (rows : List (List Nat)) (c rem s0 j : Nat) (hj : j < rem) :
    getNat (buildColSymMasksAux rows c rem s0) j = buildSymMask rows c (s0 + j) := by
  induction rem generalizing s0 j with
  | zero => cases hj
  | succ rem ih =>
    cases j with
    | zero => simp [buildColSymMasksAux, getNat]
    | succ j =>
      simp only [buildColSymMasksAux, getNat]
      rw [ih (s0 + 1) j (Nat.lt_of_succ_lt_succ hj)]
      have : s0 + 1 + j = s0 + (j + 1) := by omega
      rw [this]

theorem mem_buildColSymMasks (rows : List (List Nat)) (v c s : Nat) (hs : s < v) :
    buildSymMask rows c s ∈ buildColSymMasks rows v c := by
  unfold buildColSymMasks
  have aux : ∀ rem s0 t, s0 ≤ t → t < s0 + rem →
      buildSymMask rows c t ∈ buildColSymMasksAux rows c rem s0 := by
    intro rem
    induction rem with
    | zero => intro _ _ _ h; omega
    | succ rem ih =>
      intro s0 t hlo hhi
      simp only [buildColSymMasksAux]
      by_cases heq : t = s0
      · subst heq; exact List.mem_cons_self ..
      · exact List.mem_cons_of_mem _ (ih (s0 + 1) t (by omega) (by omega))
  exact aux v 0 s (Nat.zero_le s) (by omega)

theorem get_buildAllColsAux (rows : List (List Nat)) (v rem c0 j : Nat) (hj : j < rem) :
    getRowList (buildAllColsAux rows v rem c0) j = buildColSymMasks rows v (c0 + j) := by
  induction rem generalizing c0 j with
  | zero => cases hj
  | succ rem ih =>
    cases j with
    | zero => simp [buildAllColsAux, getRowList]
    | succ j =>
      simp only [buildAllColsAux, getRowList]
      rw [ih (c0 + 1) j (Nat.lt_of_succ_lt_succ hj)]
      have : c0 + 1 + j = c0 + (j + 1) := by omega
      rw [this]

theorem buildAllColsAux_length (rows : List (List Nat)) (v rem c0 : Nat) :
    (buildAllColsAux rows v rem c0).length = rem := by
  induction rem generalizing c0 with
  | zero => rfl
  | succ rem ih => simp [buildAllColsAux, ih]

theorem checkAndNonZeroList_sound (a : Nat) (ms : List Nat)
    (h : checkAndNonZeroList a ms = true) :
    ∀ b ∈ ms, (a &&& b) ≠ 0 := by
  induction ms with
  | nil => intro _ hm; cases hm
  | cons b bs ih =>
    simp only [checkAndNonZeroList, Bool.and_eq_true, bne_iff_ne] at h
    intro x hx
    rcases List.mem_cons.1 hx with rfl | hx'
    · exact h.1
    · exact ih h.2 x hx'

theorem checkPairMasks_sound (m1 m2 : List Nat) (h : checkPairMasks m1 m2 = true) :
    ∀ a ∈ m1, ∀ b ∈ m2, (a &&& b) ≠ 0 := by
  induction m1 with
  | nil => intro _ hm; cases hm
  | cons a as ih =>
    simp only [checkPairMasks, Bool.and_eq_true] at h
    intro x hx y hy
    rcases List.mem_cons.1 hx with rfl | hx'
    · exact checkAndNonZeroList_sound x m2 h.1 y hy
    · exact ih h.2 x hx' y hy

theorem checkCol2_sound (m1 : List Nat) (rest : List (List Nat)) (h : checkCol2 m1 rest = true) :
    ∀ j, j < rest.length → ∀ a ∈ m1, ∀ b ∈ getRowList rest j, (a &&& b) ≠ 0 := by
  induction rest with
  | nil => intro j hj; cases hj
  | cons m2 rs ih =>
    simp only [checkCol2, Bool.and_eq_true] at h
    intro j hj
    cases j with
    | zero => exact checkPairMasks_sound m1 m2 h.1
    | succ j => exact ih h.2 j (Nat.lt_of_succ_lt_succ hj)

theorem checkAllCols2_sound (cols : List (List Nat)) (h : checkAllCols2 cols = true) :
    ∀ i j, i < j → j < cols.length →
      ∀ a ∈ getRowList cols i, ∀ b ∈ getRowList cols j, (a &&& b) ≠ 0 := by
  induction cols with
  | nil => intro _ _ _ hj; cases hj
  | cons m1 rest ih =>
    simp only [checkAllCols2, Bool.and_eq_true] at h
    intro i j hij hj
    cases i with
    | zero =>
      cases j with
      | zero => omega
      | succ j => exact checkCol2_sound m1 rest h.1 j (Nat.lt_of_succ_lt_succ hj)
    | succ i =>
      cases j with
      | zero => omega
      | succ j => exact ih h.2 i j (Nat.lt_of_succ_lt_succ hij) (Nat.lt_of_succ_lt_succ hj)

theorem mem_intersectLists (m1 m2 : List Nat) (a b : Nat) (ha : a ∈ m1) (hb : b ∈ m2) :
    (a &&& b) ∈ intersectLists m1 m2 := by
  induction m1 with
  | nil => cases ha
  | cons x xs ih =>
    simp only [intersectLists, List.mem_append]
    rcases List.mem_cons.1 ha with rfl | ha'
    · exact Or.inl (List.mem_map.2 ⟨b, hb, rfl⟩)
    · exact Or.inr (ih ha')

theorem checkPairAgainstRest_sound (pm : List Nat) (rest : List (List Nat))
    (h : checkPairAgainstRest pm rest = true) :
    ∀ j, j < rest.length → ∀ ab ∈ pm, ∀ c ∈ getRowList rest j, (ab &&& c) ≠ 0 := by
  induction rest with
  | nil => intro j hj; cases hj
  | cons m3 rs ih =>
    simp only [checkPairAgainstRest, checkTripleAgainstCol, Bool.and_eq_true] at h
    intro j hj
    cases j with
    | zero => exact checkPairMasks_sound pm m3 h.1
    | succ j => exact ih h.2 j (Nat.lt_of_succ_lt_succ hj)

theorem checkCol3_sound (m1 : List Nat) (rest : List (List Nat)) (h : checkCol3 m1 rest = true) :
    ∀ j k, j < k → k < rest.length →
      ∀ a ∈ m1, ∀ b ∈ getRowList rest j, ∀ c ∈ getRowList rest k, ((a &&& b) &&& c) ≠ 0 := by
  induction rest with
  | nil => intro _ _ _ hk; cases hk
  | cons m2 rs ih =>
    simp only [checkCol3, Bool.and_eq_true] at h
    intro j k hjk hk
    cases j with
    | zero =>
      cases k with
      | zero => omega
      | succ k =>
        intro a ha b hb c hc
        exact checkPairAgainstRest_sound (intersectLists m1 m2) rs h.1 k
          (Nat.lt_of_succ_lt_succ hk) (a &&& b) (mem_intersectLists m1 m2 a b ha hb) c hc
    | succ j =>
      cases k with
      | zero => omega
      | succ k =>
        exact ih h.2 j k (Nat.lt_of_succ_lt_succ hjk) (Nat.lt_of_succ_lt_succ hk)

theorem checkAllCols3_sound (cols : List (List Nat)) (h : checkAllCols3 cols = true) :
    ∀ i j k, i < j → j < k → k < cols.length →
      ∀ a ∈ getRowList cols i, ∀ b ∈ getRowList cols j, ∀ c ∈ getRowList cols k,
        ((a &&& b) &&& c) ≠ 0 := by
  induction cols with
  | nil => intro _ _ _ _ _ hk; cases hk
  | cons m1 rest ih =>
    simp only [checkAllCols3, Bool.and_eq_true] at h
    intro i j k hij hjk hk
    cases i with
    | zero =>
      cases j with
      | zero => omega
      | succ j =>
        cases k with
        | zero => omega
        | succ k =>
          exact checkCol3_sound m1 rest h.1 j k (Nat.lt_of_succ_lt_succ hjk) (Nat.lt_of_succ_lt_succ hk)
    | succ i =>
      cases j with
      | zero => omega
      | succ j =>
        cases k with
        | zero => omega
        | succ k =>
          exact ih h.2 i j k (Nat.lt_of_succ_lt_succ hij) (Nat.lt_of_succ_lt_succ hjk) (Nat.lt_of_succ_lt_succ hk)

/-- Decode verified matrix `rows` into `Fin N → Fin k → Fin v`. -/
def decodeMatrix (N k v : Nat) (rows : List (List Nat))
    (hmat : checkMatrix N k v rows = true) : Fin N → Fin k → Fin v :=
  fun r c =>
    have hm := Bool.and_eq_true_iff.1 hmat
    have hlen : rows.length = N := beq_iff_eq.1 hm.1
    have hlt : getNat (getRowList rows r.val) c.val < v :=
      (checkMatrixRows_sound k v rows hm.2 r.val (by rw [hlen]; exact r.isLt)).2 c.val c.isLt
    ⟨getNat (getRowList rows r.val) c.val, hlt⟩

/-- **End-to-end soundness for strength-2 Covering Arrays `CA(N; 2, k, v)`**. -/
theorem validCoveringArray2_of_check (N k v : Nat) (rows : List (List Nat))
    (hchk : checkCA2 N k v rows = true) :
    ValidCoveringArray2 k v N := by
  simp only [checkCA2, Bool.and_eq_true] at hchk
  rcases hchk with ⟨hmat, hcov⟩
  have hlen : rows.length = N := beq_iff_eq.1 (Bool.and_eq_true_iff.1 hmat).1
  refine ⟨decodeMatrix N k v rows hmat, ?_⟩
  have hall := checkAllCols2_sound (buildAllCols rows k v) hcov
  have hclen : (buildAllCols rows k v).length = k := buildAllColsAux_length rows v k 0
  have hordered : ∀ (a b : Fin k), a.val < b.val → ∀ (sa sb : Fin v),
      ∃ r : Fin N, decodeMatrix N k v rows hmat r a = sa ∧ decodeMatrix N k v rows hmat r b = sb := by
    intro a b hab sa sb
    have ha_mem : buildSymMask rows a.val sa.val ∈ getRowList (buildAllCols rows k v) a.val := by
      unfold buildAllCols
      rw [get_buildAllColsAux rows v k 0 a.val a.isLt, Nat.zero_add]
      exact mem_buildColSymMasks rows v a.val sa.val sa.isLt
    have hb_mem : buildSymMask rows b.val sb.val ∈ getRowList (buildAllCols rows k v) b.val := by
      unfold buildAllCols
      rw [get_buildAllColsAux rows v k 0 b.val b.isLt, Nat.zero_add]
      exact mem_buildColSymMasks rows v b.val sb.val sb.isLt
    have hnz := hall a.val b.val hab (by rw [hclen]; exact b.isLt) _ ha_mem _ hb_mem
    rcases exists_testBit_of_ne_zero _ hnz with ⟨r, hr⟩
    rw [Nat.testBit_and] at hr
    rcases Bool.and_eq_true_iff.1 hr with ⟨hra, hrb⟩
    rcases buildSymMask_testBit rows a.val sa.val r hra with ⟨hr_lt, hval_a⟩
    rcases buildSymMask_testBit rows b.val sb.val r hrb with ⟨_, hval_b⟩
    exact ⟨⟨r, by omega⟩, Fin.ext hval_a, Fin.ext hval_b⟩
  intro c1 c2 hne s1 s2
  have hne_v : c1.val ≠ c2.val := fun h => hne (Fin.ext h)
  by_cases hlt : c1.val < c2.val
  · exact hordered c1 c2 hlt s1 s2
  · rcases hordered c2 c1 (by omega) s2 s1 with ⟨r, hr2, hr1⟩
    exact ⟨r, hr1, hr2⟩

/-- **End-to-end soundness for strength-3 Covering Arrays `CA(N; 3, k, v)`**. -/
theorem validCoveringArray3_of_check (N k v : Nat) (rows : List (List Nat))
    (hchk : checkCA3 N k v rows = true) :
    ValidCoveringArray3 k v N := by
  simp only [checkCA3, Bool.and_eq_true] at hchk
  rcases hchk with ⟨hmat, hcov⟩
  have hlen : rows.length = N := beq_iff_eq.1 (Bool.and_eq_true_iff.1 hmat).1
  refine ⟨decodeMatrix N k v rows hmat, ?_⟩
  have hall := checkAllCols3_sound (buildAllCols rows k v) hcov
  have hclen : (buildAllCols rows k v).length = k := buildAllColsAux_length rows v k 0
  have hordered : ∀ (a b c : Fin k), a.val < b.val → b.val < c.val → ∀ (sa sb sc : Fin v),
      ∃ r : Fin N,
        decodeMatrix N k v rows hmat r a = sa ∧
        decodeMatrix N k v rows hmat r b = sb ∧
        decodeMatrix N k v rows hmat r c = sc := by
    intro a b c hab hbc sa sb sc
    have ha_mem : buildSymMask rows a.val sa.val ∈ getRowList (buildAllCols rows k v) a.val := by
      unfold buildAllCols; rw [get_buildAllColsAux rows v k 0 a.val a.isLt, Nat.zero_add]
      exact mem_buildColSymMasks rows v a.val sa.val sa.isLt
    have hb_mem : buildSymMask rows b.val sb.val ∈ getRowList (buildAllCols rows k v) b.val := by
      unfold buildAllCols; rw [get_buildAllColsAux rows v k 0 b.val b.isLt, Nat.zero_add]
      exact mem_buildColSymMasks rows v b.val sb.val sb.isLt
    have hc_mem : buildSymMask rows c.val sc.val ∈ getRowList (buildAllCols rows k v) c.val := by
      unfold buildAllCols; rw [get_buildAllColsAux rows v k 0 c.val c.isLt, Nat.zero_add]
      exact mem_buildColSymMasks rows v c.val sc.val sc.isLt
    have hnz := hall a.val b.val c.val hab hbc (by rw [hclen]; exact c.isLt) _ ha_mem _ hb_mem _ hc_mem
    rcases exists_testBit_of_ne_zero _ hnz with ⟨r, hr⟩
    rw [Nat.testBit_and, Nat.testBit_and] at hr
    rcases Bool.and_eq_true_iff.1 hr with ⟨hrab, hrc⟩
    rcases Bool.and_eq_true_iff.1 hrab with ⟨hra, hrb⟩
    rcases buildSymMask_testBit rows a.val sa.val r hra with ⟨hr_lt, hval_a⟩
    rcases buildSymMask_testBit rows b.val sb.val r hrb with ⟨_, hval_b⟩
    rcases buildSymMask_testBit rows c.val sc.val r hrc with ⟨_, hval_c⟩
    exact ⟨⟨r, by omega⟩, Fin.ext hval_a, Fin.ext hval_b, Fin.ext hval_c⟩
  intro c1 c2 c3 h12 h13 h23 s1 s2 s3
  have n12 : c1.val ≠ c2.val := fun h => h12 (Fin.ext h)
  have n13 : c1.val ≠ c3.val := fun h => h13 (Fin.ext h)
  have n23 : c2.val ≠ c3.val := fun h => h23 (Fin.ext h)
  by_cases h1 : c1.val < c2.val
  · by_cases h2 : c2.val < c3.val
    · exact hordered c1 c2 c3 h1 h2 s1 s2 s3
    · by_cases h3 : c1.val < c3.val
      · rcases hordered c1 c3 c2 h3 (by omega) s1 s3 s2 with ⟨r, r1, r3, r2⟩
        exact ⟨r, r1, r2, r3⟩
      · rcases hordered c3 c1 c2 (by omega) h1 s3 s1 s2 with ⟨r, r3, r1, r2⟩
        exact ⟨r, r1, r2, r3⟩
  · by_cases h2 : c1.val < c3.val
    · rcases hordered c2 c1 c3 (by omega) h2 s2 s1 s3 with ⟨r, r2, r1, r3⟩
      exact ⟨r, r1, r2, r3⟩
    · by_cases h3 : c2.val < c3.val
      · rcases hordered c2 c3 c1 h3 (by omega) s2 s3 s1 with ⟨r, r2, r3, r1⟩
        exact ⟨r, r1, r2, r3⟩
      · rcases hordered c3 c2 c1 (by omega) (by omega) s3 s2 s1 with ⟨r, r3, r2, r1⟩
        exact ⟨r, r1, r2, r3⟩

/-! ## 2. Optimal Golomb Ruler verifier and soundness -/

def checkStrictIncLeAux (L : Nat) : Nat → List Nat → Bool
  | _, [] => true
  | prev, x :: xs => Nat.blt prev x && Nat.ble x L && checkStrictIncLeAux L x xs

def checkStrictIncLe (L : Nat) : List Nat → Bool
  | [] => true
  | x :: xs => Nat.ble x L && checkStrictIncLeAux L x xs

def checkDiffAgainst (a : Nat) : List Nat → Nat → Option Nat
  | [], dmask => some dmask
  | b :: bs, dmask =>
    let d := b - a
    if dmask.testBit d then none
    else checkDiffAgainst a bs (dmask ||| (1 <<< d))

def checkAllDiffs : List Nat → Nat → Option Nat
  | [], dmask => some dmask
  | a :: rest, dmask =>
    match checkDiffAgainst a rest dmask with
    | none => none
    | some dmask' => checkAllDiffs rest dmask'

def checkGolombRuler (k L : Nat) (marks : List Nat) : Bool :=
  (marks.length == k) && checkStrictIncLe L marks && (checkAllDiffs marks 0).isSome

theorem checkStrictIncLeAux_sound (L prev : Nat) (xs : List Nat)
    (h : checkStrictIncLeAux L prev xs = true) :
    (∀ x ∈ xs, prev < x ∧ x ≤ L) ∧
    (∀ i j : Fin xs.length, i.val < j.val → xs.get i < xs.get j) := by
  induction xs generalizing prev with
  | nil => exact ⟨(fun _ hm => nomatch hm), fun i => Fin.elim0 i⟩
  | cons x rest ih =>
    simp only [checkStrictIncLeAux, Bool.and_eq_true, Nat.blt_eq, Nat.ble_eq] at h
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

theorem checkStrictIncLe_sound (L : Nat) (xs : List Nat) (h : checkStrictIncLe L xs = true) :
    (∀ i : Fin xs.length, xs.get i ≤ L) ∧
    (∀ i j : Fin xs.length, i.val < j.val → xs.get i < xs.get j) := by
  cases xs with
  | nil => exact ⟨(fun i => Fin.elim0 i), fun i => Fin.elim0 i⟩
  | cons x rest =>
    simp only [checkStrictIncLe, Bool.and_eq_true, Nat.ble_eq] at h
    rcases checkStrictIncLeAux_sound L x rest h.2 with ⟨hmem_r, hinc_r⟩
    refine ⟨?_, ?_⟩
    · intro i
      rcases i with ⟨iv, hilt⟩
      cases iv with
      | zero => exact h.1
      | succ iv => exact (hmem_r (rest.get ⟨iv, Nat.lt_of_succ_lt_succ hilt⟩) (List.get_mem _ _)).2
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

theorem checkDiffAgainst_sound (a : Nat) (bs : List Nat) (dmask res : Nat)
    (h : checkDiffAgainst a bs dmask = some res) :
    (∀ j : Fin bs.length, dmask.testBit (bs.get j - a) = false) ∧
    (∀ j1 j2 : Fin bs.length, j1 ≠ j2 → bs.get j1 - a ≠ bs.get j2 - a) ∧
    (∀ d, res.testBit d = true ↔ dmask.testBit d = true ∨ ∃ j : Fin bs.length, bs.get j - a = d) := by
  induction bs generalizing dmask with
  | nil =>
    simp only [checkDiffAgainst, Option.some.injEq] at h
    subst h
    exact ⟨(fun j => Fin.elim0 j), (fun j => Fin.elim0 j), fun d => by simp⟩
  | cons b rest ih =>
    simp only [checkDiffAgainst] at h
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
            exact decide_eq_false_iff_not.1 (Bool.or_eq_false_iff.1 hf).2
        | succ v1 =>
          cases v2 with
          | zero =>
            have hf := hfresh ⟨v1, Nat.lt_of_succ_lt_succ h1⟩
            rw [hd'_tb] at hf
            exact Ne.symm (decide_eq_false_iff_not.1 (Bool.or_eq_false_iff.1 hf).2)
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

theorem checkAllDiffs_sound (xs : List Nat) (dmask res : Nat)
    (h : checkAllDiffs xs dmask = some res) :
    (∀ i j : Fin xs.length, i.val < j.val → dmask.testBit (xs.get j - xs.get i) = false) ∧
    (∀ i1 j1 i2 j2 : Fin xs.length, i1.val < j1.val → i2.val < j2.val →
      xs.get j1 - xs.get i1 = xs.get j2 - xs.get i2 → i1 = i2 ∧ j1 = j2) := by
  induction xs generalizing dmask with
  | nil => exact ⟨(fun i => Fin.elim0 i), fun i => Fin.elim0 i⟩
  | cons a rest ih =>
    simp only [checkAllDiffs] at h
    cases h1 : checkDiffAgainst a rest dmask with
    | none => rw [h1] at h; cases h
    | some dmask' =>
      rw [h1] at h
      rcases checkDiffAgainst_sound a rest dmask dmask' h1 with ⟨ha_fresh, ha_uniq, ha_bits⟩
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

/-- **End-to-end soundness for Optimal Golomb Rulers `G(k)`**: if `checkGolombRuler k L marks = true`,
then `ValidGolombRuler k L` (certifying `G(k) ≤ L`). -/
theorem validGolombRuler_of_check (k L : Nat) (marks : List Nat)
    (hchk : checkGolombRuler k L marks = true) :
    ValidGolombRuler k L := by
  simp only [checkGolombRuler, Bool.and_eq_true, beq_iff_eq] at hchk
  rcases hchk with ⟨⟨hlen, hinc⟩, hdiff⟩
  rcases checkStrictIncLe_sound L marks hinc with ⟨hleL, hstrict⟩
  cases hd : checkAllDiffs marks 0 with
  | none => rw [hd] at hdiff; simp at hdiff
  | some res =>
    exact ⟨marks, hlen, hleL, hstrict, (checkAllDiffs_sound marks 0 res hd).2⟩

end CombDesigns
