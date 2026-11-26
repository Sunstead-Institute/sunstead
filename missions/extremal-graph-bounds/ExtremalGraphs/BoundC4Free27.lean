import ExtremalGraphs.Spec
import ExtremalGraphs.C4Free27

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_c4free_n27 : checkSimpleGraph 27 rows_c4free_n27 = true := by
  decide +kernel

theorem edges_c4free_n27 : countEdges 27 rows_c4free_n27 = score_c4free_n27 := by
  decide +kernel

theorem c4free_c4free_n27 : checkC4Free rows_c4free_n27 = true := by
  decide +kernel

/-- Certifies `ex(27, C_4) ≥ score_c4free_n27`. -/
theorem bound_c4free_n27 : ValidC4FreeGraph 27 score_c4free_n27 :=
  validC4FreeGraph_of_check 27 score_c4free_n27 rows_c4free_n27
    simple_c4free_n27 edges_c4free_n27 c4free_c4free_n27

end ExtremalGraphs
