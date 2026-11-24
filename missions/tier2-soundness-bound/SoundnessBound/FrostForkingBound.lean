import SoundnessBound.Spec

/-!
TARGET FILE (Task: tighten_frost_forking_bound)

Baseline proven constant: `claimedFrostForkingFactor = 2000` (representing 20.00 * (t + q)^2).
Lower `claimedFrostForkingFactor` as far as mathematically possible while keeping
`frost_forking_bound` verified by Lean 4 with 0 `sorry` and 0 custom axioms.
-/

namespace SoundnessBound

def claimedFrostForkingFactor : Nat := 2000

theorem frost_forking_bound :
    ∀ t q : Nat, t ≥ 1 → q ≥ 1 →
      100 * frostForkingLoss t q ≤ claimedFrostForkingFactor * ((t + q) * (t + q)) := by
  intro t q ht hq
  unfold frostForkingLoss claimedFrostForkingFactor
  have h1 : t * (t - 1) ≤ t * t := Nat.mul_le_mul_left t (Nat.sub_le t 1)
  have h2 : (q * (q - 1)) / 2 ≤ q * (q - 1) := Nat.div_le_self _ 2
  have h3 : q * (q - 1) ≤ q * q := Nat.mul_le_mul_left q (Nat.sub_le q 1)
  have ht_le : t ≤ (t + q) * (t + q) := by
    have hge1 : 1 ≤ t + q := by omega
    calc t ≤ t + q := Nat.le_add_right t q
      _ = (t + q) * 1 := (Nat.mul_one _).symm
      _ ≤ (t + q) * (t + q) := Nat.mul_le_mul_left (t + q) hge1
  have hq_le : q ≤ (t + q) * (t + q) := by
    have hge1 : 1 ≤ t + q := by omega
    calc q ≤ t + q := Nat.le_add_left q t
      _ = (t + q) * 1 := (Nat.mul_one _).symm
      _ ≤ (t + q) * (t + q) := Nat.mul_le_mul_left (t + q) hge1
  have htt_le : t * t ≤ (t + q) * (t + q) :=
    Nat.mul_le_mul (Nat.le_add_right t q) (Nat.le_add_right t q)
  have hqq_le : q * q ≤ (t + q) * (t + q) :=
    Nat.mul_le_mul (Nat.le_add_left q t) (Nat.le_add_left q t)
  have htq_le : t * q ≤ (t + q) * (t + q) :=
    Nat.mul_le_mul (Nat.le_add_right t q) (Nat.le_add_left q t)
  omega

end SoundnessBound
