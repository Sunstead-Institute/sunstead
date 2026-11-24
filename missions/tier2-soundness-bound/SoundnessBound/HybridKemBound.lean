import SoundnessBound.Spec

/-!
TARGET FILE (Task: tighten_hybrid_kem_bound)

Baseline proven constant: `claimedHybridKemFactor = 1200` (representing 12.00 * (n + q)^2).
Lower `claimedHybridKemFactor` as far as mathematically possible while keeping
`hybrid_kem_bound` verified by Lean 4 with 0 `sorry` and 0 custom axioms.
-/

namespace SoundnessBound

def claimedHybridKemFactor : Nat := 1200

theorem hybrid_kem_bound :
    ∀ n q : Nat, n ≥ 1 → q ≥ 1 →
      100 * hybridKemLoss n q ≤ claimedHybridKemFactor * ((n + q) * (n + q)) := by
  intro n q hn hq
  unfold hybridKemLoss claimedHybridKemFactor
  have h1 : (n * (n - 1)) / 2 ≤ n * (n - 1) := Nat.div_le_self _ 2
  have h2 : n * (n - 1) ≤ n * n := Nat.mul_le_mul_left n (Nat.sub_le n 1)
  have h3 : (q * q) / 3 ≤ q * q := Nat.div_le_self _ 3
  have hn_le : n ≤ (n + q) * (n + q) := by
    have hge1 : 1 ≤ n + q := by omega
    calc n ≤ n + q := Nat.le_add_right n q
      _ = (n + q) * 1 := (Nat.mul_one _).symm
      _ ≤ (n + q) * (n + q) := Nat.mul_le_mul_left (n + q) hge1
  have hq_le : q ≤ (n + q) * (n + q) := by
    have hge1 : 1 ≤ n + q := by omega
    calc q ≤ n + q := Nat.le_add_left q n
      _ = (n + q) * 1 := (Nat.mul_one _).symm
      _ ≤ (n + q) * (n + q) := Nat.mul_le_mul_left (n + q) hge1
  have hnn_le : n * n ≤ (n + q) * (n + q) :=
    Nat.mul_le_mul (Nat.le_add_right n q) (Nat.le_add_right n q)
  have hqq_le : q * q ≤ (n + q) * (n + q) :=
    Nat.mul_le_mul (Nat.le_add_left q n) (Nat.le_add_left q n)
  have hnq_le : n * q ≤ (n + q) * (n + q) :=
    Nat.mul_le_mul (Nat.le_add_right n q) (Nat.le_add_left q n)
  omega

end SoundnessBound
