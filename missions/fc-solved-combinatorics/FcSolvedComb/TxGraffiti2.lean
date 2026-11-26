/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Arxiv/2507.17780/2.lean#L73-L79
Upstream category: research solved | AMS: 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedComb.Spec

namespace FcSolvedComb.TxGraffiti2

open SimpleGraph

theorem tx_graffiti_conjecture_2 :
    ¬ ∀ (V : Type) [Fintype V] [DecidableEq V] (G : SimpleGraph V)
      [DecidableRel G.Adj] (_hConn : G.Connected)
      (_hDeg : G.maxDegree ≤ 3)
      (_hNotK4 : G = ⊤ → Fintype.card V ≠ 4),
      zeroForcingNumber G ≤ G.indepNum + 1 := by
  sorry

end FcSolvedComb.TxGraffiti2
