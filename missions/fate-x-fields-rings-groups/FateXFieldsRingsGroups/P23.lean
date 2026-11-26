import FateXFieldsRingsGroups.Spec

namespace Problem23

local instance (p : Nat.Primes) : NeZero p.1 := ⟨p.2.ne_zero⟩
local instance (p : Nat.Primes) : IsDomain (ZMod p) := @ZMod.instIsDomain p ⟨p.2⟩

theorem ratio_tendsto_one_of_irreducible (f : Polynomial ℤ) (h_irr : Irreducible f) :
    Function.rightLim
    (fun (s : ℝ) ↦
    (tsum (fun p : Nat.Primes ↦ (f.rootSet (ZMod p)).ncard * ((p : ℝ) ^ (-s)))) /
    (tsum (fun p : Nat.Primes ↦ (p : ℝ) ^ (-s)))) 1 = 1 := by
  sorry

end Problem23
