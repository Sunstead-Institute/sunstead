import ExtremalGraphs.Spec
import ExtremalGraphs.C4Free25

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_c4free_n25 : checkSimpleGraph 25 rows_c4free_n25 = true := by
  decide +kernel

theorem edges_c4free_n25 : countEdges 25 rows_c4free_n25 = score_c4free_n25 := by
  decide +kernel

theorem c4free_c4free_n25 : checkC4Free rows_c4free_n25 = true := by
  decide +kernel

/-- Certifies `ex(25, C_4) ≥ score_c4free_n25`. -/
theorem bound_c4free_n25 : ValidC4FreeGraph 25 score_c4free_n25 :=
  validC4FreeGraph_of_check 25 score_c4free_n25 rows_c4free_n25
    simple_c4free_n25 edges_c4free_n25 c4free_c4free_n25

end ExtremalGraphs
