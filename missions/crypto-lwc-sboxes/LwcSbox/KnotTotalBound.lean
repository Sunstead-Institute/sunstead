import LwcSbox.Spec
import LwcSbox.KnotTotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem knotTotal_wf : wellFormed 4 knotTotalGates knotTotalOutputs = true := by
  decide +kernel

theorem knotTotal_metric : knotTotalGates.length = knotTotalScore := by
  decide +kernel

theorem knotTotal_check : checkCircuitBV 4 initRevBV4 knotTable knotTotalGates knotTotalOutputs = true := by
  decide +kernel

theorem knot_total_gates_bound : ValidTotalCircuit 4 knotSbox knotTotalScore :=
  ⟨knotTotalGates, knotTotalOutputs, knotTotal_wf, knotTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 knotTable knotSbox
      initRevBV4_ok knotTable_ok knotTotalGates knotTotalOutputs knotTotal_check⟩

end LwcSbox
