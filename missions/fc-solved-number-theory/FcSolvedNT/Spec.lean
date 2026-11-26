/-
FROZEN UPSTREAM SPECIFICATION — extracted verbatim from:
  Repository: https://github.com/google-deepmind/formal-conjectures
  Commit:     5bd8bfb9def462c19a87d2d275af3db3341dc727
  License:    Apache-2.0
  Note: Only Apache-2.0 Lean 4 definitions from pinned upstream files are
  included; third-party prose docstrings are omitted.
-/
import Mathlib

namespace FcSolvedNT

namespace DivisorErrorHardy
open Filter Asymptotics Real
noncomputable def divisorSummatory (x : ℝ) : ℝ :=
  ∑ n ∈ Finset.Icc 1 ⌊x⌋₊, (n.divisors.card : ℝ)
noncomputable def divisorError (x : ℝ) : ℝ :=
  divisorSummatory x - x * Real.log x - (2 * eulerMascheroniConstant - 1) * x
end DivisorErrorHardy

namespace CarmichaelTotientBound
open Nat
def CarmichaelTotientFor (n : ℕ) : Prop := ∃ m : ℕ, m ≠ n ∧ φ m = φ n
end CarmichaelTotientBound

namespace Erdos1057AGP
open Nat Real Filter Set
open scoped Topology Asymptotics
noncomputable def carmichaelCounting (x : ℝ) : ℝ :=
  ({n : ℕ | IsCarmichael n ∧ (n : ℝ) ≤ x}.ncard : ℝ)
end Erdos1057AGP

namespace Erdos325Wooley
open Asymptotics Filter
def IsSumThreePower (k n : ℕ) : Prop := ∃ a b c, a ^ k + b ^ k + c ^ k = n
noncomputable def cardIsSumThreePowerBelow (k x : ℕ) : ℕ :=
  {n ∈ Set.Iic x | IsSumThreePower k n}.ncard
end Erdos325Wooley

namespace ImaginaryClassNumberOne
open Polynomial
def IsClassNumberOne (d : ℤ) : Prop :=
  ∃ (h₂ : Irreducible (X ^ 2 - C (d : ℚ))),
  have := Fact.mk h₂
  NumberField.classNumber (AdjoinRoot (X ^ 2 - C (d : ℚ))) = 1
end ImaginaryClassNumberOne

namespace LonelyRunnerTao2017
noncomputable def deltaTuple {n : ℕ} (v : Fin n → ℤ) : ℝ :=
  sSup { δ : ℝ | ∃ t : AddCircle (1 : ℝ), ∀ i : Fin n, δ ≤ dist (v i • t : AddCircle (1 : ℝ)) 0 }
noncomputable def deltaGap (n : ℕ) : ℝ :=
  sInf { d : ℝ | ∃ v : Fin n ↪ ℤ, (∀ i : Fin n, v i ≠ 0) ∧ d = deltaTuple v }
end LonelyRunnerTao2017

namespace Erdos12Sarkozy
open Filter Set
abbrev IsGood (A : Set ℕ) : Prop := A.Infinite ∧
  ∀ᵉ (a ∈ A) (b ∈ A) (c ∈ A), a ∣ b + c → a < b →
  a < c → b = c
end Erdos12Sarkozy

namespace Erdos4PrimeGaps
open Real
def Erdos4For (C : ℝ) : Prop :=
  {n : ℕ | (n + 1).nth Nat.Prime - n.nth Nat.Prime >
    C * log (log n) * log (log (log (log n))) / (log (log (log n))) ^ 2 * log n}.Infinite
end Erdos4PrimeGaps

namespace Erdos711Interval
open Filter Asymptotics
def HasDivisibleDistinctTuple (n m L : ℕ) : Prop :=
  ∃ a : Fin n → ℕ,
    Function.Injective a ∧
      ∀ i : Fin n, m < a i ∧ a i < m + L ∧ (i.val + 1) ∣ a i
def IsMinimalIntervalLength (n m L : ℕ) : Prop :=
  HasDivisibleDistinctTuple n m L ∧
    ∀ L', HasDivisibleDistinctTuple n m L' → L ≤ L'
end Erdos711Interval

namespace OeisA287616
def A (n : ℕ) : Prop :=
  ∃ x y z : ℕ, n = x * (x + 1) / 2 + y * (3 * y + 1) / 2 + z * (5 * z + 1) / 2
end OeisA287616

namespace Erdos848NonSquarefree
def NonSquarefreeProductProp (A : Finset ℕ) : Prop :=
  ∀ a ∈ A, ∀ b ∈ A, ¬Squarefree (a * b + 1)
def A₇ (N : ℕ) : Finset ℕ :=
  (Finset.range N).filter (fun n => n % 25 = 7)
def Erdos848For (N : ℕ) : Prop :=
  ∀ A : Finset ℕ, A ⊆ Finset.range N → NonSquarefreeProductProp A →
    A.card ≤ (A₇ N).card
end Erdos848NonSquarefree

namespace ZetaSecondMoment
open Complex Filter Real
open scoped Asymptotics Nat
noncomputable def moment (k : ℕ) (T : ℝ) : ℝ :=
  1/T * ∫ t in (0 : ℝ)..(T), ‖riemannZeta (1/2 + I * t)‖ ^ (2 * k)
end ZetaSecondMoment

end FcSolvedNT
