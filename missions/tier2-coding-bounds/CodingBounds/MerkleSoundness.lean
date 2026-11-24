import CodingBounds.Spec

/-!
TARGET FILE (Task: tighten_merkle_soundness)

Baseline proven constant: `claimedMerkleFactor = 1800` (representing 18.00 * (h + q)^2).
Lower `claimedMerkleFactor` as far as mathematically possible while keeping
`merkle_soundness_bound` verified by Lean 4 with 0 `sorry` and 0 custom axioms.
-/

namespace CodingBounds

def claimedMerkleFactor : Nat := 1800

theorem merkle_soundness_bound :
    ∀ h q : Nat, h ≥ 1 → q ≥ 1 →
      100 * merkleSoundnessLoss h q ≤ claimedMerkleFactor * ((h + q) * (h + q)) := by
  intro h q hh hq
  unfold merkleSoundnessLoss claimedMerkleFactor
  have h1 : (q * (q - 1)) / 2 ≤ q * (q - 1) := Nat.div_le_self _ 2
  have h2 : q * (q - 1) ≤ q * q := Nat.mul_le_mul_left q (Nat.sub_le q 1)
  have hh_le : h ≤ (h + q) * (h + q) := by
    have hge1 : 1 ≤ h + q := by omega
    calc h ≤ h + q := Nat.le_add_right h q
      _ = (h + q) * 1 := (Nat.mul_one _).symm
      _ ≤ (h + q) * (h + q) := Nat.mul_le_mul_left (h + q) hge1
  have hq_le : q ≤ (h + q) * (h + q) := by
    have hge1 : 1 ≤ h + q := by omega
    calc q ≤ h + q := Nat.le_add_left q h
      _ = (h + q) * 1 := (Nat.mul_one _).symm
      _ ≤ (h + q) * (h + q) := Nat.mul_le_mul_left (h + q) hge1
  have hhh_le : h * h ≤ (h + q) * (h + q) :=
    Nat.mul_le_mul (Nat.le_add_right h q) (Nat.le_add_right h q)
  have hqq_le : q * q ≤ (h + q) * (h + q) :=
    Nat.mul_le_mul (Nat.le_add_left q h) (Nat.le_add_left q h)
  have hhq_le : h * q ≤ (h + q) * (h + q) :=
    Nat.mul_le_mul (Nat.le_add_right h q) (Nat.le_add_left q h)
  omega

end CodingBounds
