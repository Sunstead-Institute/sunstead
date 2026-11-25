import RankF2.Spec

namespace B334
open Finset

def vecOfMask (n m : ℕ) : Fin n → ZMod 2 :=
  fun p => if m.testBit p.val then 1 else 0

def zb (b : Bool) : ZMod 2 := if b then 1 else 0

/-- bit `i` of `v` in `ZMod 2` -/
def zbit (v i : ℕ) : ZMod 2 := zb (v.testBit i)

theorem zb_xor (a b : Bool) : zb (xor a b) = zb a + zb b := by cases a <;> cases b <;> decide
theorem zb_and (a b : Bool) : zb (a && b) = zb a * zb b := by cases a <;> cases b <;> decide

theorem sum_getD {α : Type*} (L : List α) (d : α) (g : α → ZMod 2) {N : ℕ} (hN : L.length = N) :
    ∑ s : Fin N, g (L.getD s d) = (L.map g).sum := by
  subst hN
  induction L with
  | nil => simp
  | cons t L ih =>
    show ∑ s : Fin (L.length + 1), g ((t :: L).getD s d) = _
    rw [Fin.sum_univ_succ]
    simp only [Fin.val_zero, Fin.val_succ, List.getD_cons_zero, List.getD_cons_succ, ih, List.map_cons,
      List.sum_cons]

/-- entry `(x, y, z)` of `∑ₛ aₛ ⊗ bₛ ⊗ cₛ` for a list of mask triples `(aₛ, bₛ, cₛ)`, as a parity -/
def entryN : List (ℕ × ℕ × ℕ) → ℕ → ℕ → ℕ → Bool
  | [], _, _, _ => false
  | t :: L, x, y, z => xor (t.1.testBit x && t.2.1.testBit y && t.2.2.testBit z) (entryN L x y z)

def tgtShape (n m p x y z : ℕ) : Bool :=
  decide (x % m = y / p ∧ y % p = z / n ∧ z % n = x / m)

theorem zb_entryN (L : List (ℕ × ℕ × ℕ)) (x y z : ℕ) :
    zb (entryN L x y z) = (L.map (fun t => zbit t.1 x * zbit t.2.1 y * zbit t.2.2 z)).sum := by
  induction L with
  | nil => simp [entryN, zb]
  | cons t L ih =>
    simp only [entryN, zb_xor, zb_and, ih, List.map_cons, List.sum_cons, zbit]

theorem mmShape_eq_zb (n m p : ℕ) (x : Fin (n * m)) (y : Fin (m * p)) (z : Fin (p * n)) :
    (mmT n m p) x y z = zb (tgtShape n m p x.val y.val z.val) := by
  simp only [mmT, tgtShape, zb, decide_eq_true_eq]

theorem rankLE_of_certificate (n m p : ℕ) (L : List (ℕ × ℕ × ℕ)) {N : ℕ} (hN : L.length = N)
    (hcert : ∀ x < n * m, ∀ y < m * p, ∀ z < p * n, entryN L x y z = tgtShape n m p x y z) :
    RankLE (mmT n m p) N := by
  refine ⟨fun s => vecOfMask (n * m) (L.getD s (0, 0, 0)).1,
    fun s => vecOfMask (m * p) (L.getD s (0, 0, 0)).2.1,
    fun s => vecOfMask (p * n) (L.getD s (0, 0, 0)).2.2, ?_⟩
  funext x y z
  have h := sum_getD (N := N) L (0, 0, 0)
    (fun t => zbit t.1 x.val * zbit t.2.1 y.val * zbit t.2.2 z.val) hN
  rw [← zb_entryN, hcert x.val x.isLt y.val y.isLt z.val z.isLt, ← mmShape_eq_zb] at h
  rw [← h]
  simp only [Finset.sum_apply, outer3]
  rfl

end B334
