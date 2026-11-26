/-
FROZEN UPSTREAM SPECIFICATION — extracted verbatim from:
  Repository: https://github.com/google-deepmind/formal-conjectures
  Commit:     5bd8bfb9def462c19a87d2d275af3db3341dc727
  License:    Apache-2.0
  Note: Only Apache-2.0 Lean 4 definitions from pinned upstream files are
  included; third-party prose docstrings are omitted.
-/
import Mathlib

namespace FcSolvedComb

namespace Erdos813BucicSudakov
open Filter Asymptotics
def EverySevenHasTriangle {n : ℕ} (G : SimpleGraph (Fin n)) : Prop :=
  ∀ S : Finset (Fin n), S.card = 7 → ∃ t ⊆ S, G.IsNClique 3 t
noncomputable def h (n : ℕ) : ℕ :=
  sInf {k : ℕ | ∃ G : SimpleGraph (Fin n), EverySevenHasTriangle G ∧ G.cliqueNum = k}
end Erdos813BucicSudakov

namespace Erdos920TriangleFree
open Real Filter
noncomputable def f (k n : ℕ) : ℕ :=
  sSup {(G.chromaticNumber) | (G : SimpleGraph (Fin n)) (_ : G.CliqueFree k)}
end Erdos920TriangleFree

namespace Erdos295Straus
open scoped Real
noncomputable abbrev k (N : ℕ) : ℕ :=
  sInf {k | ∃ n : Fin k → ℕ, (∀ i, N ≤ n i) ∧ StrictMono n ∧ ∑ i, (1 / n i : ℝ) = 1}
end Erdos295Straus

namespace Erdos494ProdMultiset
open Filter
noncomputable def prodMultiset (A : Finset ℂ) (k : ℕ) : Multiset ℂ :=
  ((A.powersetCard k).val.map (fun s => s.prod id))
end Erdos494ProdMultiset

namespace Erdos882Antichain
open Finset
def IsSubsetSumAntichain (A : Finset ℕ) : Prop :=
  ∀ S₁ ⊆ A, ∀ S₂ ⊆ A, S₁.Nonempty → S₂.Nonempty → S₁ ≠ S₂ →
    ¬ (∑ a ∈ S₁, a) ∣ (∑ a ∈ S₂, a)
noncomputable def maxAntichainCard (n : ℕ) : ℕ :=
  sSup {k | ∃ A ⊆ Finset.Icc 1 n, IsSubsetSumAntichain A ∧ A.card = k}
end Erdos882Antichain

namespace TuDeng
def binaryWeight (n : ℕ) : ℕ := (Nat.digits 2 n).sum
end TuDeng

namespace TxGraffiti2
open SimpleGraph
noncomputable def zeroForcingStep {V : Type*} [Fintype V] [DecidableEq V]
    (G : SimpleGraph V) [DecidableRel G.Adj] (S : Finset V) : Finset V :=
  S ∪ Finset.univ.filter fun w =>
    w ∉ S ∧ ∃ v ∈ S, G.Adj v w ∧ ∀ u, G.Adj v u → u ∉ S → u = w
noncomputable def zeroForcingClosure {V : Type*} [Fintype V] [DecidableEq V]
    (G : SimpleGraph V) [DecidableRel G.Adj] (S : Finset V) : Finset V :=
  (zeroForcingStep G)^[Fintype.card V] S
def IsZeroForcingSet {V : Type*} [Fintype V] [DecidableEq V]
    (G : SimpleGraph V) [DecidableRel G.Adj] (S : Finset V) : Prop :=
  zeroForcingClosure G S = Finset.univ
noncomputable def zeroForcingNumber {V : Type*} [Fintype V] [DecidableEq V]
    (G : SimpleGraph V) [DecidableRel G.Adj] : ℕ :=
  sInf {k | ∃ S : Finset V, S.card = k ∧ IsZeroForcingSet G S}
end TxGraffiti2

namespace GyarfasSumnerPath
open SimpleGraph
def IsChiBoundedBy {W : Type} (T : SimpleGraph W) (f : ℕ → ℕ) : Prop :=
  ∀ {V : Type} [Fintype V] [DecidableEq V] (G : SimpleGraph V) [DecidableRel G.Adj],
    ¬ SimpleGraph.IsIndContained T G → G.chromaticNumber ≤ f G.cliqueNum
end GyarfasSumnerPath

namespace Erdos61P5
open Filter
open SimpleGraph
open Real
def IsErdosHajnalLowerBound {α : Type*} [Fintype α] [DecidableEq α]
  (H : SimpleGraph α) (f : ℕ → ℝ) : Prop :=
  ∀ᶠ n in atTop, ∀ G : SimpleGraph (Fin n),
    (¬∃ g : α ↪ Fin n, H = G.comap g) → G.indepNum ≥ f n ∨ G.cliqueNum ≥ f n
end Erdos61P5

namespace Green76Rectangles
open scoped Finset
def HitsRichRectangles (k : ℕ) (A A' : Finset (ℝ × ℝ)) : Prop :=
  ∀ a b : ℝ × ℝ, k ≤ #{p ∈ A | p ∈ Set.Icc a b} → ∃ p ∈ A', p ∈ Set.Icc a b
end Green76Rectangles

namespace Erdos926AKS
open Filter Asymptotics SimpleGraph
def H (k : ℕ) : SimpleGraph (Unit ⊕ (Fin k ⊕ {p : Fin k × Fin k // p.1 < p.2})) where
  Adj x y :=
    match x, y with
    | Sum.inl _, Sum.inr (Sum.inl _) => True
    | Sum.inr (Sum.inl _), Sum.inl _ => True
    | Sum.inr (Sum.inl i), Sum.inr (Sum.inr p) => i = p.1.1 ∨ i = p.1.2
    | Sum.inr (Sum.inr p), Sum.inr (Sum.inl i) => i = p.1.1 ∨ i = p.1.2
    | _, _ => False
  symm := by
    constructor
    intro x y h
    rcases x with _ | _ | _ <;> rcases y with _ | _ | _ <;> simp_all
  loopless := by
    constructor
    intro x
    rcases x with _ | _ | _ <;> simp
end Erdos926AKS

namespace Erdos781Wave
open Filter Asymptotics
def IsDescendingWave {k : ℕ} (x : Fin k → ℕ) : Prop :=
  StrictMono x ∧
    ∀ i j l : Fin k, (i : ℕ) + 1 = j → (j : ℕ) + 1 = l → x i + x l ≤ 2 * x j
noncomputable def f (k : ℕ) : ℕ :=
  sInf {n | ∀ c : Fin n → Fin 2, ∃ x : Fin k → Fin n,
    IsDescendingWave (fun i ↦ (x i : ℕ)) ∧ ∃ γ, ∀ i, c (x i) = γ}
end Erdos781Wave

namespace MmsPokrovskiy
open Finset
noncomputable def nonnegSubsetCount (n k : ℕ) (x : Fin n → ℝ) : ℕ :=
  ((univ : Finset (Fin n)).powersetCard k).filter (fun S => 0 ≤ ∑ i ∈ S, x i) |>.card
end MmsPokrovskiy

end FcSolvedComb
