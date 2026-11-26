/-
FROZEN UPSTREAM SPECIFICATION — extracted verbatim from:
  Repository: https://github.com/google-deepmind/formal-conjectures
  Commit:     5bd8bfb9def462c19a87d2d275af3db3341dc727
  License:    Apache-2.0
  Note: Only Apache-2.0 Lean 4 definitions from pinned upstream files are
  included; third-party prose docstrings are omitted.
-/
import Mathlib

namespace FcOpenOeisClassics

namespace AbcConjecture
def radical (n : ℕ) : ℕ := n.primeFactors.prod id
end AbcConjecture

namespace BealConjecture
def bealConjecture : Prop := ∀ {A B C x y z : ℕ},
    A ≠ 0 → B ≠ 0 → C ≠ 0 → 2 < x → 2 < y → 2 < z →
    A^x + B^y = C^z → 1 < Finset.gcd {A, B, C} id
end BealConjecture

namespace FermatCatalan
open scoped Function
def FermatCatalanSet' : Set (Fin 6 → ℕ) :=
    { f : Fin 6 → ℕ |
        (∀ i, 0 < f i) ∧
        (({0, 1, 2} : Set <| Fin 6).Pairwise (Nat.Coprime on f)) ∧
        (f 0) ^ (f 3) + (f 1) ^ (f 4) = (f 2) ^ (f 5) ∧
        ∑ i ∈ Finset.Icc 3 5, (1 / f i : ℝ) < 1 }
def FermatCatalanSet : Set (ℕ × ℕ × ℕ) :=
    (fun f => ((f 0) ^ (f 3), (f 1) ^ (f 4), (f 2) ^ (f 5))) '' FermatCatalanSet'
def fermatCatalanConjecture : Prop :=
  FermatCatalanSet.Finite
end FermatCatalan

namespace GilbreathConjecture
noncomputable def d : ℕ → (ℕ → ℕ)
  | 0 => fun n ↦ n.nth Nat.Prime
  | k + 1 => fun n ↦ Int.natAbs (d k (n + 1) - d k n)
end GilbreathConjecture

namespace BuchiProblem
def IsBuchi (M : ℕ) : Prop :=
  ∀ x a : ℤ, (∀ n ∈ Finset.range M, IsSquare ((x + (n : ℤ)) ^ 2 + a)) → a = 0
end BuchiProblem

end FcOpenOeisClassics
