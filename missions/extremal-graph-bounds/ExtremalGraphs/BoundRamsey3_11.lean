import ExtremalGraphs.Spec
import ExtremalGraphs.Ramsey3_11

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_ramsey_3_11 : checkSimpleGraph score_ramsey_3_11 rows_ramsey_3_11 = true := by
  decide +kernel

theorem noK3_ramsey_3_11 : checkNoClique score_ramsey_3_11 3 rows_ramsey_3_11 = true := by
  decide +kernel

theorem noI11_ramsey_3_11 : checkNoClique score_ramsey_3_11 11 (compRows score_ramsey_3_11 rows_ramsey_3_11) = true := by
  decide +kernel

/-- Certifies `R(3, 11) ≥ score_ramsey_3_11 + 1`. -/
theorem bound_ramsey_3_11 : ValidRamseyGraph 3 11 score_ramsey_3_11 :=
  validRamseyGraph_of_check 3 11 score_ramsey_3_11 rows_ramsey_3_11
    simple_ramsey_3_11 noK3_ramsey_3_11 noI11_ramsey_3_11

end ExtremalGraphs
