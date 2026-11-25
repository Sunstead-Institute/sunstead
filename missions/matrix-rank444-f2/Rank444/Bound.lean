import Rank444.Spec
import Rank444.Certificate

namespace B334
open Finset
set_option maxRecDepth 100000
set_option maxHeartbeats 10000000

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

/-! ## Verification of the submitted decomposition -/

/-- entry `(x, y, z)` of `∑ₛ aₛ ⊗ bₛ ⊗ cₛ` for a list of mask triples `(aₛ, bₛ, cₛ)`, as a parity -/
def entryN : List (ℕ × ℕ × ℕ) → ℕ → ℕ → ℕ → Bool
  | [], _, _, _ => false
  | t :: L, x, y, z => xor (t.1.testBit x && t.2.1.testBit y && t.2.2.testBit z) (entryN L x y z)

/-- entry `(x, y, z)` of mmT 4 4 4 -/
def tgtN (x y z : ℕ) : Bool := decide (x % 4 = y / 4 ∧ y % 4 = z / 4 ∧ z % 4 = x / 4)

theorem certificate_correct : ∀ x < 16, ∀ y < 16, ∀ z < 16, entryN certificate x y z = tgtN x y z := by
  decide +kernel

theorem zb_entryN (L : List (ℕ × ℕ × ℕ)) (x y z : ℕ) :
    zb (entryN L x y z) = (L.map (fun t => zbit t.1 x * zbit t.2.1 y * zbit t.2.2 z)).sum := by
  induction L with
  | nil => simp [entryN, zb]
  | cons t L ih =>
    simp only [entryN, zb_xor, zb_and, ih, List.map_cons, List.sum_cons, zbit]

theorem mm444_eq_zb (x : Fin (4 * 4)) (y : Fin (4 * 4)) (z : Fin (4 * 4)) :
    (mmT 4 4 4) x y z = zb (tgtN x.val y.val z.val) := by
  simp only [mmT, tgtN, zb, decide_eq_true_eq]

/-- The submitted table gives an upper bound equal to its length. -/
theorem bound : RankLE (mmT 4 4 4) score := by
  refine ⟨fun s => vecOfMask (4 * 4) (certificate.getD s (0, 0, 0)).1,
    fun s => vecOfMask (4 * 4) (certificate.getD s (0, 0, 0)).2.1,
    fun s => vecOfMask (4 * 4) (certificate.getD s (0, 0, 0)).2.2, ?_⟩
  funext x y z
  have h := sum_getD (N := score) certificate (0, 0, 0)
    (fun t => zbit t.1 x.val * zbit t.2.1 y.val * zbit t.2.2 z.val) rfl
  rw [← zb_entryN, certificate_correct x.val x.isLt y.val y.isLt z.val z.isLt, ← mm444_eq_zb] at h
  rw [← h]
  simp only [Finset.sum_apply, outer3]
  rfl

end B334
