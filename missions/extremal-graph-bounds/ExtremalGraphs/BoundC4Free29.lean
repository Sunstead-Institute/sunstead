import ExtremalGraphs.Spec
import ExtremalGraphs.C4Free29

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_c4free_n29 : checkSimpleGraph 29 rows_c4free_n29 = true := by
  decide +kernel

theorem edges_c4free_n29 : countEdges 29 rows_c4free_n29 = score_c4free_n29 := by
  decide +kernel

theorem c4free_c4free_n29 : checkC4Free rows_c4free_n29 = true := by
  decide +kernel

/-- Certifies `ex(29, C_4) ≥ score_c4free_n29`. -/
theorem bound_c4free_n29 : ValidC4FreeGraph 29 score_c4free_n29 :=
  validC4FreeGraph_of_check 29 score_c4free_n29 rows_c4free_n29
    simple_c4free_n29 edges_c4free_n29 c4free_c4free_n29

end ExtremalGraphs
