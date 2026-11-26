import LwcSbox.Spec
import LwcSbox.SaturninTotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem saturninTotal_wf : wellFormed 4 saturninTotalGates saturninTotalOutputs = true := by
  decide +kernel

theorem saturninTotal_metric : saturninTotalGates.length = saturninTotalScore := by
  decide +kernel

theorem saturninTotal_check : checkCircuitBV 4 initRevBV4 saturninTable saturninTotalGates saturninTotalOutputs = true := by
  decide +kernel

theorem saturnin_total_gates_bound : ValidTotalCircuit 4 saturninSbox saturninTotalScore :=
  ⟨saturninTotalGates, saturninTotalOutputs, saturninTotal_wf, saturninTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 saturninTable saturninSbox
      initRevBV4_ok saturninTable_ok saturninTotalGates saturninTotalOutputs saturninTotal_check⟩

end LwcSbox
