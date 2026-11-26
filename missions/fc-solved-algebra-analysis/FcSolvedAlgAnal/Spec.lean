/-
FROZEN UPSTREAM SPECIFICATION — extracted verbatim from:
  Repository: https://github.com/google-deepmind/formal-conjectures
  Commit:     5bd8bfb9def462c19a87d2d275af3db3341dc727
  License:    Apache-2.0
  Note: Only Apache-2.0 Lean 4 definitions from pinned upstream files are
  included; third-party prose docstrings are omitted.
-/
import Mathlib

namespace FcSolvedAlgAnal

namespace Erdos114Lemniscate
open Polynomial MeasureTheory Filter
def lemniscate (p : ℂ[X]) : Set ℂ := {z | ‖p.eval z‖ = 1}
noncomputable def lemniscateLength (p : ℂ[X]) : ENNReal := μH[1] (lemniscate p)
end Erdos114Lemniscate

namespace ConjClassSizesS3
open ConjClasses
noncomputable def conjClassCard {G : Type*} [Monoid G] (c : ConjClasses G) : ℕ :=
  Nat.card c.carrier
def HasDistinctConjClassSizes (G : Type*) [Group G] [Fintype G] : Prop :=
  Function.Injective (conjClassCard (G := G))
end ConjClassSizesS3

namespace Green54Gaussian
open MeasureTheory ProbabilityTheory
open scoped Pointwise ENNReal
noncomputable def gaussianMeasureInf : Measure (ℕ → ℝ) :=
  Measure.infinitePi (fun _ : ℕ => gaussianReal 0 1)
end Green54Gaussian

namespace PierceBirkhoffDim2
open scoped Polynomial
def IsSemiAlgebraic {n : ℕ} (S : Set (Fin n → ℝ)) : Prop :=
  ∃ (ι : Type) (p₀ p₁ : ι → Finset (MvPolynomial (Fin n) ℝ)), Finite ι ∧
    S = ⋃ i, {x | (∀ p ∈ p₀ i, MvPolynomial.eval x p = 0) ∧
      ∀ p ∈ p₁ i, MvPolynomial.eval x p > 0}
def IsPiecewiseMvPolynomial {n : ℕ} (f : (Fin n → ℝ) → ℝ) : Prop :=
  ∃ (ι : Type) (P : ι → Set (Fin n → ℝ))
    (g : ι → MvPolynomial (Fin n) ℝ),
    Finite ι ∧
    (∀ i, IsClosed (P i)) ∧
    (∀ i, IsSemiAlgebraic (P i)) ∧
    (⋃ i, P i) = Set.univ ∧
    ∀ᵉ (i : ι) (x ∈ P i), f x = MvPolynomial.eval x (g i)
end PierceBirkhoffDim2

namespace ShelahSpencer01
open FirstOrder Filter MeasureTheory Topology
noncomputable def sparseProbability (n : ℕ) (α : ℝ) (hα : 0 < α) : unitInterval :=
  ⟨(n : ℝ) ^ (-α), Real.rpow_nonneg (Nat.cast_nonneg n) (-α), by
    cases n with
    | zero => simpa using Real.zero_rpow_le_one (-α)
    | succ n =>
        exact Real.rpow_le_one_of_one_le_of_nonpos
          (by exact_mod_cast Nat.succ_le_succ (Nat.zero_le n)) (by simp [hα.le])⟩
noncomputable def sparseRandomGraph (n : ℕ) (α : ℝ) (hα : 0 < α) :
    Measure (SimpleGraph (Fin n)) :=
  SimpleGraph.binomialRandom (Fin n) (sparseProbability n α hα)
end ShelahSpencer01

namespace Erdos120Finite
open Set MeasureTheory
def Erdos120For (A : Set ℝ) : Prop := ∃ E : Set ℝ,
  MeasurableSet E ∧ 0 < volume E ∧ ∀ a b : ℝ, a ≠ 0 → ¬ .image (fun x => a * x + b) A ⊆ E
end Erdos120Finite

namespace Hilbert17Motzkin
open Real MvPolynomial
noncomputable def f : MvPolynomial (Fin 2) ℝ :=
  X 0 ^ 4 * X 1 ^ 2 + X 0 ^ 2 * X 1 ^ 4 - 3 * X 0 ^ 2 * X 1 ^ 2 + 1
end Hilbert17Motzkin

namespace VoronovskajaBernstein
open Topology Filter MeasureTheory ProbabilityTheory Real unitInterval Polynomial
noncomputable def bernsteinTail (n k : ℕ) : Polynomial ℝ :=
  ∑ j ∈ Finset.Icc k n, bernsteinPolynomial ℝ n j
noncomputable def bezierBernstein (n : ℕ) (α : ℝ) (f : ℝ → ℝ) (x : ℝ) : ℝ :=
  ∑ k ∈ Finset.range (n + 1),
    f (k / n) * ((bernsteinTail n k).eval x ^ α - (bernsteinTail n (k + 1)).eval x ^ α)
end VoronovskajaBernstein

namespace ErdosUlamSolymosi
open EuclideanSpace
def PairwiseRationalDistances (S : Set (EuclideanSpace ℝ (Fin 2))) : Prop :=
  ∀ p ∈ S, ∀ q ∈ S, ∃ r : ℚ, dist p q = (r : ℝ)
end ErdosUlamSolymosi

namespace Green87PermLimit
open Filter Asymptotics Topology
def FixesSet {n : ℕ} (σ : Equiv.Perm (Fin n)) (k : ℕ) : Prop :=
  ∃ s : Finset (Fin n), s.card = k ∧ s.image σ = s
noncomputable def i (n k : ℕ) : ℝ :=
  (Nat.card {σ : Equiv.Perm (Fin n) // FixesSet σ k} : ℝ) / (Nat.card (Equiv.Perm (Fin n)) : ℝ)
noncomputable def δ : ℝ := 1 - (1 + Real.log (Real.log 2)) / Real.log 2
end Green87PermLimit

namespace GammaSubgroup33
open Equiv.Perm
noncomputable def signDiffHom (m n : ℕ) : Equiv.Perm (Fin m) × Equiv.Perm (Fin n) →* ℤˣ :=
  (sign.comp (MonoidHom.fst _ _)) * (sign.comp (MonoidHom.snd _ _))⁻¹
noncomputable def gammaSubgroup (m n : ℕ) : Subgroup (Equiv.Perm (Fin m) × Equiv.Perm (Fin n)) :=
  (signDiffHom m n).ker
end GammaSubgroup33

namespace Erdos1046Diameter
open Polynomial Metric
def lemniscate (f : ℂ[X]) : Set ℂ := {z | ‖f.eval z‖ < 1}
def closedLemniscate (f : ℂ[X]) : Set ℂ := {z | ‖f.eval z‖ ≤ 1}
end Erdos1046Diameter

namespace Erdos1132Lebesgue
open Filter MeasureTheory
noncomputable def lagrangeBasis (n : ℕ) (x : ℕ → ℝ) (k : ℕ) (t : ℝ) : ℝ :=
  (∏ i ∈ (Finset.range n).erase k, (t - x i)) / ∏ i ∈ (Finset.range n).erase k, (x k - x i)
noncomputable def lebesgueFunction (n : ℕ) (x : ℕ → ℝ) (t : ℝ) : ℝ :=
  ∑ k ∈ Finset.range n, |lagrangeBasis n x k t|
end Erdos1132Lebesgue

end FcSolvedAlgAnal
