import ExtremalGraphs.Spec
import ExtremalGraphs.Ramsey3_8

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_ramsey_3_8 : checkSimpleGraph score_ramsey_3_8 rows_ramsey_3_8 = true := by
  decide +kernel

theorem noK3_ramsey_3_8 : checkNoClique score_ramsey_3_8 3 rows_ramsey_3_8 = true := by
  decide +kernel

theorem noI8_ramsey_3_8 : checkNoClique score_ramsey_3_8 8 (compRows score_ramsey_3_8 rows_ramsey_3_8) = true := by
  decide +kernel

/-- Certifies `R(3, 8) ≥ score_ramsey_3_8 + 1`. -/
theorem bound_ramsey_3_8 : ValidRamseyGraph 3 8 score_ramsey_3_8 :=
  validRamseyGraph_of_check 3 8 score_ramsey_3_8 rows_ramsey_3_8
    simple_ramsey_3_8 noK3_ramsey_3_8 noI8_ramsey_3_8

end ExtremalGraphs
