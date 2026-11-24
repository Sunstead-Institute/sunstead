import CodingBounds.Spec

/-!
TARGET FILE (Task: tighten_sponge_birthday)

Baseline proven constant: `claimedSpongeFactor = 1200` (representing 12.00 * (q + b)^2).
Lower `claimedSpongeFactor` as far as mathematically possible while keeping
`sponge_birthday_bound` verified by Lean 4 with 0 `sorry` and 0 custom axioms.
-/

namespace CodingBounds

def claimedSpongeFactor : Nat := 1200

theorem sponge_birthday_bound :
    ∀ q b : Nat, q ≥ 1 → b ≥ 1 →
      100 * spongeBirthdayLoss q b ≤ claimedSpongeFactor * ((q + b) * (q + b)) := by
  intro q b hq hb
  unfold spongeBirthdayLoss claimedSpongeFactor
  have h1 : (q * (q - 1)) / 2 ≤ q * (q - 1) := Nat.div_le_self _ 2
  have h2 : q * (q - 1) ≤ q * q := Nat.mul_le_mul_left q (Nat.sub_le q 1)
  have h3 : (b * (b - 1)) / 2 ≤ b * (b - 1) := Nat.div_le_self _ 2
  have h4 : b * (b - 1) ≤ b * b := Nat.mul_le_mul_left b (Nat.sub_le b 1)
  have hq_le : q ≤ (q + b) * (q + b) := by
    have hge1 : 1 ≤ q + b := by omega
    calc q ≤ q + b := Nat.le_add_right q b
      _ = (q + b) * 1 := (Nat.mul_one _).symm
      _ ≤ (q + b) * (q + b) := Nat.mul_le_mul_left (q + b) hge1
  have hb_le : b ≤ (q + b) * (q + b) := by
    have hge1 : 1 ≤ q + b := by omega
    calc b ≤ q + b := Nat.le_add_left b q
      _ = (q + b) * 1 := (Nat.mul_one _).symm
      _ ≤ (q + b) * (q + b) := Nat.mul_le_mul_left (q + b) hge1
  have hqq_le : q * q ≤ (q + b) * (q + b) :=
    Nat.mul_le_mul (Nat.le_add_right q b) (Nat.le_add_right q b)
  have hbb_le : b * b ≤ (q + b) * (q + b) :=
    Nat.mul_le_mul (Nat.le_add_left b q) (Nat.le_add_left b q)
  have hqb_le : q * b ≤ (q + b) * (q + b) :=
    Nat.mul_le_mul (Nat.le_add_right q b) (Nat.le_add_left b q)
  omega

end CodingBounds
