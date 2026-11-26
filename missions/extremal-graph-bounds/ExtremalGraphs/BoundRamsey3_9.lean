import ExtremalGraphs.Spec
import ExtremalGraphs.Ramsey3_9

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_ramsey_3_9 : checkSimpleGraph score_ramsey_3_9 rows_ramsey_3_9 = true := by
  decide +kernel

theorem noK3_ramsey_3_9 : checkNoClique score_ramsey_3_9 3 rows_ramsey_3_9 = true := by
  decide +kernel

theorem noI9_ramsey_3_9 : checkNoClique score_ramsey_3_9 9 (compRows score_ramsey_3_9 rows_ramsey_3_9) = true := by
  decide +kernel

/-- Certifies `R(3, 9) ≥ score_ramsey_3_9 + 1`. -/
theorem bound_ramsey_3_9 : ValidRamseyGraph 3 9 score_ramsey_3_9 :=
  validRamseyGraph_of_check 3 9 score_ramsey_3_9 rows_ramsey_3_9
    simple_ramsey_3_9 noK3_ramsey_3_9 noI9_ramsey_3_9

end ExtremalGraphs
