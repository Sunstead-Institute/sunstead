/-
FROZEN UPSTREAM SPECIFICATION — copied verbatim from:
  Repository: https://github.com/AlexKontorovich/PrimeNumberTheoremAnd
  Commit:     e9906138410f8f76ca66b9bc252d0993f3ee348c
  Files:
    - PrimeNumberTheoremAnd/IwaniecKowalskiCh1.lean (tau, sigmaR, liouville, IsCompletelyMultiplicative)
    - PrimeNumberTheoremAnd/Wiener.lean (AbsolutelyContinuous)
  License:    Apache-2.0
-/
import Mathlib.NumberTheory.LSeries.Dirichlet
import Mathlib.NumberTheory.LSeries.Nonvanishing
import Mathlib.Analysis.Fourier.RiemannLebesgueLemma
import Mathlib.Topology.EMetricSpace.BoundedVariation
import Mathlib.MeasureTheory.Integral.IntervalIntegral.Basic

open ArithmeticFunction hiding log
open Finset Nat Real MeasureTheory FourierTransform
open scoped zeta sigma
open scoped ArithmeticFunction.omega ArithmeticFunction.Omega
open scoped ArithmeticFunction.Moebius
open scoped LSeries.notation

namespace PntFoundations

/-- `τ` (tau) is the divisor count function, equal to `σ 0`. -/
abbrev tau : ArithmeticFunction ℕ := σ 0

@[inherit_doc tau]
scoped notation "τ" => PntFoundations.tau

/-- Divisor power sum with exponents in an arbitrary semiring `R`. -/
noncomputable def sigmaR {R : Type*} [Semiring R] [HPow R R R] (s : R) : ArithmeticFunction R where
  toFun := fun n ↦ ∑ d ∈ n.divisors, (d : R) ^ s
  map_zero' := by simp

scoped notation "σᴿ" => PntFoundations.sigmaR

/-- Liouville function: `λ(n) = (-1)^Ω(n)`. -/
def liouville : ArithmeticFunction ℤ :=
  toArithmeticFunction (fun n => (-1 : ℤ) ^ Ω n)

/-- Define Complete Multiplicativity for an arithmetic function. -/
def IsCompletelyMultiplicative (f : ArithmeticFunction ℝ) : Prop :=
  f 1 = 1 ∧ ∀ a b, f (a * b) = f a * f b

/-- Absolute continuity predicate from `PrimeNumberTheoremAnd/Wiener.lean:335`. -/
noncomputable def AbsolutelyContinuous (f : ℝ → ℂ) : Prop := (∀ᵐ x, DifferentiableAt ℝ f x) ∧
  ∀ a b : ℝ, f b - f a = ∫ t in a..b, deriv f t

end PntFoundations
