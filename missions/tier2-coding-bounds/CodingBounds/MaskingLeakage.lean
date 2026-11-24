import CodingBounds.Spec

/-!
TARGET FILE (Task: tighten_masking_leakage)

Baseline proven constant: `claimedMaskingFactor = 1500` (representing 15.00 * (s + g)^2).
Lower `claimedMaskingFactor` as far as mathematically possible while keeping
`masking_leakage_bound` verified by Lean 4 with 0 `sorry` and 0 custom axioms.
-/

namespace CodingBounds

def claimedMaskingFactor : Nat := 1500

theorem masking_leakage_bound :
    ∀ s g : Nat, s ≥ 1 → g ≥ 1 →
      100 * maskingLeakage s g ≤ claimedMaskingFactor * ((s + g) * (s + g)) := by
  intro s g hs hg
  unfold maskingLeakage claimedMaskingFactor
  have h1 : s * (s - 1) ≤ s * s := Nat.mul_le_mul_left s (Nat.sub_le s 1)
  have h2 : g * (g - 1) ≤ g * g := Nat.mul_le_mul_left g (Nat.sub_le g 1)
  have hs_le : s ≤ (s + g) * (s + g) := by
    have hge1 : 1 ≤ s + g := by omega
    calc s ≤ s + g := Nat.le_add_right s g
      _ = (s + g) * 1 := (Nat.mul_one _).symm
      _ ≤ (s + g) * (s + g) := Nat.mul_le_mul_left (s + g) hge1
  have hg_le : g ≤ (s + g) * (s + g) := by
    have hge1 : 1 ≤ s + g := by omega
    calc g ≤ s + g := Nat.le_add_left g s
      _ = (s + g) * 1 := (Nat.mul_one _).symm
      _ ≤ (s + g) * (s + g) := Nat.mul_le_mul_left (s + g) hge1
  have hss_le : s * s ≤ (s + g) * (s + g) :=
    Nat.mul_le_mul (Nat.le_add_right s g) (Nat.le_add_right s g)
  have hgg_le : g * g ≤ (s + g) * (s + g) :=
    Nat.mul_le_mul (Nat.le_add_left g s) (Nat.le_add_left g s)
  have hsg_le : s * g ≤ (s + g) * (s + g) :=
    Nat.mul_le_mul (Nat.le_add_right s g) (Nat.le_add_left g s)
  omega

end CodingBounds
