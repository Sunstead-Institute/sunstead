import ExtremalGraphs.Spec
import ExtremalGraphs.C4Free36

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_c4free_n36 : checkSimpleGraph 36 rows_c4free_n36 = true := by
  decide +kernel

theorem edges_c4free_n36 : countEdges 36 rows_c4free_n36 = score_c4free_n36 := by
  decide +kernel

theorem c4free_c4free_n36 : checkC4Free rows_c4free_n36 = true := by
  decide +kernel

/-- Certifies `ex(36, C_4) ≥ score_c4free_n36`. -/
theorem bound_c4free_n36 : ValidC4FreeGraph 36 score_c4free_n36 :=
  validC4FreeGraph_of_check 36 score_c4free_n36 rows_c4free_n36
    simple_c4free_n36 edges_c4free_n36 c4free_c4free_n36

end ExtremalGraphs
