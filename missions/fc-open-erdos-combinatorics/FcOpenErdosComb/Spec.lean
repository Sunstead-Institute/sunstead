/-
FROZEN UPSTREAM SPECIFICATION — extracted verbatim from:
  Repository: https://github.com/google-deepmind/formal-conjectures
  Commit:     5bd8bfb9def462c19a87d2d275af3db3341dc727
  License:    Apache-2.0
  Note: Only Apache-2.0 Lean 4 definitions from pinned upstream files are
  included; third-party prose docstrings are omitted.
-/
import Mathlib

namespace FcOpenErdosComb

namespace BabaiSeress
def cayleyGraph {G : Type*} [Group G] (S : Set G) : SimpleGraph G :=
  SimpleGraph.fromRel (fun g h => g⁻¹ * h ∈ S)
noncomputable def groupDiam (G : Type*) [Group G] [Fintype G] : ℕ :=
  sSup { d : ℕ | ∃ S : Set G, Subgroup.closure S = ⊤ ∧ (cayleyGraph S).diam = d }
end BabaiSeress

namespace BarkerSequence
def aperiodicAutocorrelation (a : List ℤ) (k : ℕ) : ℤ :=
  (List.zipWith (· * ·) a (a.drop k)).sum
def IsBarkerSequence (a : List ℤ) : Prop :=
  (∀ x ∈ a, x = 1 ∨ x = -1) ∧
    ∀ k : ℕ, 0 < k → k < a.length → |aperiodicAutocorrelation a k| ≤ 1
end BarkerSequence

namespace Green76HittingSet
open scoped Finset
def HitsRichRectangles (k : ℕ) (A A' : Finset (ℝ × ℝ)) : Prop :=
  ∀ a b : ℝ × ℝ, k ≤ #{p ∈ A | p ∈ Set.Icc a b} → ∃ p ∈ A', p ∈ Set.Icc a b
end Green76HittingSet

namespace WeighingMatrix
def IsWeighingMatrix {n : ℕ} (w : ℕ) (W : Matrix (Fin n) (Fin n) ℤ) : Prop :=
  (∀ i j, W i j = -1 ∨ W i j = 0 ∨ W i j = 1) ∧
    W * W.transpose = (w : ℤ) • 1
end WeighingMatrix

namespace ManickamMiklosSinghi
open Finset
noncomputable def nonnegSubsetCount (n k : ℕ) (x : Fin n → ℝ) : ℕ :=
  ((univ : Finset (Fin n)).powersetCard k).filter (fun S => 0 ≤ ∑ i ∈ S, x i) |>.card
end ManickamMiklosSinghi

namespace GyarfasSumner
open SimpleGraph
def IsChiBoundedBy {W : Type} (T : SimpleGraph W) (f : ℕ → ℕ) : Prop :=
  ∀ {V : Type} [Fintype V] [DecidableEq V] (G : SimpleGraph V) [DecidableRel G.Adj],
    ¬ SimpleGraph.IsIndContained T G → G.chromaticNumber ≤ f G.cliqueNum
end GyarfasSumner

namespace Green59SmoothSum
open Filter
def IsSmooth (y : ℝ) (m : ℕ) : Prop :=
  ∀ p ∈ m.primeFactors, (p : ℝ) ≤ y
end Green59SmoothSum

end FcOpenErdosComb
