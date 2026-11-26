import ExtremalGraphs.Spec
import ExtremalGraphs.Ramsey3_10

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_ramsey_3_10 : checkSimpleGraph score_ramsey_3_10 rows_ramsey_3_10 = true := by
  decide +kernel

theorem noK3_ramsey_3_10 : checkNoClique score_ramsey_3_10 3 rows_ramsey_3_10 = true := by
  decide +kernel

theorem noI10_ramsey_3_10 : checkNoClique score_ramsey_3_10 10 (compRows score_ramsey_3_10 rows_ramsey_3_10) = true := by
  decide +kernel

/-- Certifies `R(3, 10) ≥ score_ramsey_3_10 + 1`. -/
theorem bound_ramsey_3_10 : ValidRamseyGraph 3 10 score_ramsey_3_10 :=
  validRamseyGraph_of_check 3 10 score_ramsey_3_10 rows_ramsey_3_10
    simple_ramsey_3_10 noK3_ramsey_3_10 noI10_ramsey_3_10

end ExtremalGraphs
