import CodingBounds.Spec

/-!
TARGET FILE (Task: tighten_rs_list_bound)

Baseline proven constant: `claimedRsListFactor = 1400` (representing 14.00 * (n + k)^2).
Lower `claimedRsListFactor` as far as mathematically possible while keeping
`rs_list_bound` verified by Lean 4 with 0 `sorry` and 0 custom axioms.
-/

namespace CodingBounds

def claimedRsListFactor : Nat := 1400

theorem rs_list_bound :
    ∀ n k : Nat, n ≥ 1 → k ≥ 1 →
      100 * rsListLoss n k ≤ claimedRsListFactor * ((n + k) * (n + k)) := by
  intro n k hn hk
  unfold rsListLoss claimedRsListFactor
  have h1 : n * (n - 1) ≤ n * n := Nat.mul_le_mul_left n (Nat.sub_le n 1)
  have h2 : (k * (k - 1)) / 2 ≤ k * (k - 1) := Nat.div_le_self _ 2
  have h3 : k * (k - 1) ≤ k * k := Nat.mul_le_mul_left k (Nat.sub_le k 1)
  have hn_le : n ≤ (n + k) * (n + k) := by
    have hge1 : 1 ≤ n + k := by omega
    calc n ≤ n + k := Nat.le_add_right n k
      _ = (n + k) * 1 := (Nat.mul_one _).symm
      _ ≤ (n + k) * (n + k) := Nat.mul_le_mul_left (n + k) hge1
  have hk_le : k ≤ (n + k) * (n + k) := by
    have hge1 : 1 ≤ n + k := by omega
    calc k ≤ n + k := Nat.le_add_left k n
      _ = (n + k) * 1 := (Nat.mul_one _).symm
      _ ≤ (n + k) * (n + k) := Nat.mul_le_mul_left (n + k) hge1
  have hnn_le : n * n ≤ (n + k) * (n + k) :=
    Nat.mul_le_mul (Nat.le_add_right n k) (Nat.le_add_right n k)
  have hkk_le : k * k ≤ (n + k) * (n + k) :=
    Nat.mul_le_mul (Nat.le_add_left k n) (Nat.le_add_left k n)
  have hnk_le : n * k ≤ (n + k) * (n + k) :=
    Nat.mul_le_mul (Nat.le_add_right n k) (Nat.le_add_left k n)
  omega

end CodingBounds
