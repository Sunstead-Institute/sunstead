import ExtremalGraphs.Spec
import ExtremalGraphs.Ramsey5_5

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_ramsey_5_5 : checkSimpleGraph score_ramsey_5_5 rows_ramsey_5_5 = true := by
  decide +kernel

theorem noK5_ramsey_5_5 : checkNoClique score_ramsey_5_5 5 rows_ramsey_5_5 = true := by
  decide +kernel

theorem noI5_ramsey_5_5 : checkNoClique score_ramsey_5_5 5 (compRows score_ramsey_5_5 rows_ramsey_5_5) = true := by
  decide +kernel

/-- Certifies `R(5, 5) ≥ score_ramsey_5_5 + 1`. -/
theorem bound_ramsey_5_5 : ValidRamseyGraph 5 5 score_ramsey_5_5 :=
  validRamseyGraph_of_check 5 5 score_ramsey_5_5 rows_ramsey_5_5
    simple_ramsey_5_5 noK5_ramsey_5_5 noI5_ramsey_5_5

end ExtremalGraphs
