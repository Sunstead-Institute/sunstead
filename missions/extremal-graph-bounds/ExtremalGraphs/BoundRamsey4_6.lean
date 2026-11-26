import ExtremalGraphs.Spec
import ExtremalGraphs.Ramsey4_6

namespace ExtremalGraphs

set_option maxRecDepth 200000
set_option maxHeartbeats 4000000

theorem simple_ramsey_4_6 : checkSimpleGraph score_ramsey_4_6 rows_ramsey_4_6 = true := by
  decide +kernel

theorem noK4_ramsey_4_6 : checkNoClique score_ramsey_4_6 4 rows_ramsey_4_6 = true := by
  decide +kernel

theorem noI6_ramsey_4_6 : checkNoClique score_ramsey_4_6 6 (compRows score_ramsey_4_6 rows_ramsey_4_6) = true := by
  decide +kernel

/-- Certifies `R(4, 6) ≥ score_ramsey_4_6 + 1`. -/
theorem bound_ramsey_4_6 : ValidRamseyGraph 4 6 score_ramsey_4_6 :=
  validRamseyGraph_of_check 4 6 score_ramsey_4_6 rows_ramsey_4_6
    simple_ramsey_4_6 noK4_ramsey_4_6 noI6_ramsey_4_6

end ExtremalGraphs
