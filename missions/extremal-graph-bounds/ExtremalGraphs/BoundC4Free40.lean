import ExtremalGraphs.Spec
import ExtremalGraphs.C4Free40

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_c4free_n40 : checkSimpleGraph 40 rows_c4free_n40 = true := by
  decide +kernel

theorem edges_c4free_n40 : countEdges 40 rows_c4free_n40 = score_c4free_n40 := by
  decide +kernel

theorem c4free_c4free_n40 : checkC4Free rows_c4free_n40 = true := by
  decide +kernel

/-- Certifies `ex(40, C_4) ≥ score_c4free_n40`. -/
theorem bound_c4free_n40 : ValidC4FreeGraph 40 score_c4free_n40 :=
  validC4FreeGraph_of_check 40 score_c4free_n40 rows_c4free_n40
    simple_c4free_n40 edges_c4free_n40 c4free_c4free_n40

end ExtremalGraphs
