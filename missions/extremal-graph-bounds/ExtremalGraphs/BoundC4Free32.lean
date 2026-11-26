import ExtremalGraphs.Spec
import ExtremalGraphs.C4Free32

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_c4free_n32 : checkSimpleGraph 32 rows_c4free_n32 = true := by
  decide +kernel

theorem edges_c4free_n32 : countEdges 32 rows_c4free_n32 = score_c4free_n32 := by
  decide +kernel

theorem c4free_c4free_n32 : checkC4Free rows_c4free_n32 = true := by
  decide +kernel

/-- Certifies `ex(32, C_4) ≥ score_c4free_n32`. -/
theorem bound_c4free_n32 : ValidC4FreeGraph 32 score_c4free_n32 :=
  validC4FreeGraph_of_check 32 score_c4free_n32 rows_c4free_n32
    simple_c4free_n32 edges_c4free_n32 c4free_c4free_n32

end ExtremalGraphs
