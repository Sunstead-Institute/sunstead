import SoundnessBound.Spec

/-!
TARGET FILE (Task: tighten_multi_user_bound)

Baseline proven constant: `claimedMultiUserFactor = 1000` (representing 10.00 * (u + q)^2).
Lower `claimedMultiUserFactor` as far as mathematically possible while keeping
`multi_user_bound` verified by Lean 4 with 0 `sorry` and 0 custom axioms.
-/

namespace SoundnessBound

def claimedMultiUserFactor : Nat := 1000

theorem multi_user_bound :
    ∀ u q : Nat, u ≥ 1 → q ≥ 1 →
      100 * multiUserLoss u q ≤ claimedMultiUserFactor * ((u + q) * (u + q)) := by
  intro u q hu hq
  unfold multiUserLoss claimedMultiUserFactor
  have h1 : (q * (q - 1)) / 2 ≤ q * (q - 1) := Nat.div_le_self _ 2
  have h2 : q * (q - 1) ≤ q * q := Nat.mul_le_mul_left q (Nat.sub_le q 1)
  have h3 : (q * q) / 4 ≤ q * q := Nat.div_le_self _ 4
  have hq_le : q ≤ (u + q) * (u + q) := by
    have hge1 : 1 ≤ u + q := by omega
    calc q ≤ u + q := Nat.le_add_left q u
      _ = (u + q) * 1 := (Nat.mul_one _).symm
      _ ≤ (u + q) * (u + q) := Nat.mul_le_mul_left (u + q) hge1
  have hu_le : u ≤ (u + q) * (u + q) := by
    have hge1 : 1 ≤ u + q := by omega
    calc u ≤ u + q := Nat.le_add_right u q
      _ = (u + q) * 1 := (Nat.mul_one _).symm
      _ ≤ (u + q) * (u + q) := Nat.mul_le_mul_left (u + q) hge1
  have hqq_le : q * q ≤ (u + q) * (u + q) :=
    Nat.mul_le_mul (Nat.le_add_left q u) (Nat.le_add_left q u)
  have huq_le : u * q ≤ (u + q) * (u + q) :=
    Nat.mul_le_mul (Nat.le_add_right u q) (Nat.le_add_left q u)
  omega

end SoundnessBound
