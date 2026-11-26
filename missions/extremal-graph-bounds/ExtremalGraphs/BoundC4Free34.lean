import ExtremalGraphs.Spec
import ExtremalGraphs.C4Free34

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_c4free_n34 : checkSimpleGraph 34 rows_c4free_n34 = true := by
  decide +kernel

theorem edges_c4free_n34 : countEdges 34 rows_c4free_n34 = score_c4free_n34 := by
  decide +kernel

theorem c4free_c4free_n34 : checkC4Free rows_c4free_n34 = true := by
  decide +kernel

/-- Certifies `ex(34, C_4) ≥ score_c4free_n34`. -/
theorem bound_c4free_n34 : ValidC4FreeGraph 34 score_c4free_n34 :=
  validC4FreeGraph_of_check 34 score_c4free_n34 rows_c4free_n34
    simple_c4free_n34 edges_c4free_n34 c4free_c4free_n34

end ExtremalGraphs
