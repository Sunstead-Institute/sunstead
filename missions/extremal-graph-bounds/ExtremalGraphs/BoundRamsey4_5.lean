import ExtremalGraphs.Spec
import ExtremalGraphs.Ramsey4_5

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_ramsey_4_5 : checkSimpleGraph score_ramsey_4_5 rows_ramsey_4_5 = true := by
  decide +kernel

theorem noK4_ramsey_4_5 : checkNoClique score_ramsey_4_5 4 rows_ramsey_4_5 = true := by
  decide +kernel

theorem noI5_ramsey_4_5 : checkNoClique score_ramsey_4_5 5 (compRows score_ramsey_4_5 rows_ramsey_4_5) = true := by
  decide +kernel

/-- Certifies `R(4, 5) ≥ score_ramsey_4_5 + 1`. -/
theorem bound_ramsey_4_5 : ValidRamseyGraph 4 5 score_ramsey_4_5 :=
  validRamseyGraph_of_check 4 5 score_ramsey_4_5 rows_ramsey_4_5
    simple_ramsey_4_5 noK4_ramsey_4_5 noI5_ramsey_4_5

end ExtremalGraphs
