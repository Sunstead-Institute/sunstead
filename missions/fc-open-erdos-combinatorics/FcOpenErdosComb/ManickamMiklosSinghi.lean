/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Paper/ManickamMiklosSinghiConjecture.lean#L56-L59
Upstream category: research open | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcOpenErdosComb.Spec

namespace FcOpenErdosComb.ManickamMiklosSinghi

open Finset

theorem manickam_miklos_singhi_conjecture :
    ∀ (n k : ℕ), 1 ≤ k → 4 * k ≤ n → ∀ x : Fin n → ℝ, ∑ i, x i = 0 →
      (n - 1).choose (k - 1) ≤ nonnegSubsetCount n k x := by
  sorry

end FcOpenErdosComb.ManickamMiklosSinghi
