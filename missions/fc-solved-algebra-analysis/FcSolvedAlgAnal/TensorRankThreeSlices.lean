/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Arxiv/0805.3777/TensorRank.lean#L291-L293
Upstream category: research solved | AMS: 15
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.TensorRankThreeSlices

theorem cprank_le_of_three_slices {n : ℕ} (hn : 1 ≤ n) (T : Holor ℂ [n, n, 3]) :
    T.cprank ≤ 2 * n - 1 := by
  sorry

end FcSolvedAlgAnal.TensorRankThreeSlices
