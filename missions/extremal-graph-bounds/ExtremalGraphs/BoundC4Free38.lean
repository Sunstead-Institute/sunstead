import ExtremalGraphs.Spec
import ExtremalGraphs.C4Free38

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_c4free_n38 : checkSimpleGraph 38 rows_c4free_n38 = true := by
  decide +kernel

theorem edges_c4free_n38 : countEdges 38 rows_c4free_n38 = score_c4free_n38 := by
  decide +kernel

theorem c4free_c4free_n38 : checkC4Free rows_c4free_n38 = true := by
  decide +kernel

/-- Certifies `ex(38, C_4) ≥ score_c4free_n38`. -/
theorem bound_c4free_n38 : ValidC4FreeGraph 38 score_c4free_n38 :=
  validC4FreeGraph_of_check 38 score_c4free_n38 rows_c4free_n38
    simple_c4free_n38 edges_c4free_n38 c4free_c4free_n38

end ExtremalGraphs
