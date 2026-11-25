/-
FROZEN UPSTREAM SPECIFICATION — copied verbatim from:
  Repository: https://github.com/Verified-zkEVM/ArkLib
  Commit:     2934c834177ee4de50b9df5ce58509a8529fbf88
  File:       ArkLib/Data/CodingTheory/ProximityGap/CapacityBounds/NearCapacity.lean (L287-L291)
  Issue:      https://github.com/Verified-zkEVM/ArkLib/issues/1352
  License:    Apache-2.0

In ArkLib's `ArkLib/Data/CodingTheory/ProximityGap/CapacityBounds.lean`, the coding-theory
construction `exists_rs_epsCa_large_near_capacity_of_primes` is already fully proved; the sole
remaining `sorry` in `exists_rs_epsCa_large_near_capacity` is proving `NearCapacityPrimeSupply c`
for every `c > 0`.
-/
import Mathlib.Basic.NNReal.Defs
import Mathlib.Analysis.SpecialFunctions.Pow.Real
import Mathlib.Data.Nat.Prime.Defs

open scoped NNReal

namespace ArkLibNearCapacity

/-- The supply of primes behind the near-capacity family: for some `β > max(c + 2, 12/5)` and
infinitely many `K`, there is a prime `p ≡ 1 (mod 2^K)` with `n^β ≤ p ≤ 2n^β`, `n = 2^K`. -/
def NearCapacityPrimeSupply (c : ℝ≥0) : Prop :=
  ∃ β : ℝ, max ((c : ℝ) + 2) (12 / 5) < β ∧ ∀ K₀ : ℕ, ∃ K ≥ K₀, ∃ p : ℕ,
    p.Prime ∧ 2 ^ K ∣ p - 1 ∧ ((2 : ℝ) ^ K) ^ β ≤ p ∧ (p : ℝ) ≤ 2 * ((2 : ℝ) ^ K) ^ β

end ArkLibNearCapacity
