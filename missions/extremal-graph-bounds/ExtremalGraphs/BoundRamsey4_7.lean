import ExtremalGraphs.Spec
import ExtremalGraphs.Ramsey4_7

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_ramsey_4_7 : checkSimpleGraph score_ramsey_4_7 rows_ramsey_4_7 = true := by
  decide +kernel

theorem noK4_ramsey_4_7 : checkNoClique score_ramsey_4_7 4 rows_ramsey_4_7 = true := by
  decide +kernel

theorem noI7_ramsey_4_7 : checkNoClique score_ramsey_4_7 7 (compRows score_ramsey_4_7 rows_ramsey_4_7) = true := by
  decide +kernel

/-- Certifies `R(4, 7) ≥ score_ramsey_4_7 + 1`. -/
theorem bound_ramsey_4_7 : ValidRamseyGraph 4 7 score_ramsey_4_7 :=
  validRamseyGraph_of_check 4 7 score_ramsey_4_7 rows_ramsey_4_7
    simple_ramsey_4_7 noK4_ramsey_4_7 noI7_ramsey_4_7

end ExtremalGraphs
