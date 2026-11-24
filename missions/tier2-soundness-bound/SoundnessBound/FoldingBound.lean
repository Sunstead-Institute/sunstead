import SoundnessBound.Spec

/-!
TARGET FILE (Task: tighten_folding_bound)

Baseline proven constant: `claimedFoldingFactor = 1600` (representing 16.00 * (d + r)^2).
Lower `claimedFoldingFactor` as far as mathematically possible while keeping
`folding_bound` verified by Lean 4 with 0 `sorry` and 0 custom axioms.
-/

namespace SoundnessBound

def claimedFoldingFactor : Nat := 1600

theorem folding_bound :
    ∀ d r : Nat, d ≥ 1 → r ≥ 1 →
      100 * foldingError d r ≤ claimedFoldingFactor * ((d + r) * (d + r)) := by
  intro d r hd hr
  unfold foldingError claimedFoldingFactor
  have h1 : (d * (d - 1)) / 2 ≤ d * (d - 1) := Nat.div_le_self _ 2
  have h2 : d * (d - 1) ≤ d * d := Nat.mul_le_mul_left d (Nat.sub_le d 1)
  have hd_le : d ≤ (d + r) * (d + r) := by
    have hge1 : 1 ≤ d + r := by omega
    calc d ≤ d + r := Nat.le_add_right d r
      _ = (d + r) * 1 := (Nat.mul_one _).symm
      _ ≤ (d + r) * (d + r) := Nat.mul_le_mul_left (d + r) hge1
  have hr_le : r ≤ (d + r) * (d + r) := by
    have hge1 : 1 ≤ d + r := by omega
    calc r ≤ d + r := Nat.le_add_left r d
      _ = (d + r) * 1 := (Nat.mul_one _).symm
      _ ≤ (d + r) * (d + r) := Nat.mul_le_mul_left (d + r) hge1
  have hdd_le : d * d ≤ (d + r) * (d + r) :=
    Nat.mul_le_mul (Nat.le_add_right d r) (Nat.le_add_right d r)
  have hrr_le : r * r ≤ (d + r) * (d + r) :=
    Nat.mul_le_mul (Nat.le_add_left r d) (Nat.le_add_left r d)
  have hdr_le : d * r ≤ (d + r) * (d + r) :=
    Nat.mul_le_mul (Nat.le_add_right d r) (Nat.le_add_left r d)
  omega

end SoundnessBound
