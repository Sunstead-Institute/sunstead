import LwcSbox.Spec
import LwcSbox.PresentTotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem presentTotal_wf : wellFormed 4 presentTotalGates presentTotalOutputs = true := by
  decide +kernel

theorem presentTotal_metric : presentTotalGates.length = presentTotalScore := by
  decide +kernel

theorem presentTotal_check : checkCircuitBV 4 initRevBV4 presentTable presentTotalGates presentTotalOutputs = true := by
  decide +kernel

theorem present_total_gates_bound : ValidTotalCircuit 4 presentSbox presentTotalScore :=
  ⟨presentTotalGates, presentTotalOutputs, presentTotal_wf, presentTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 presentTable presentSbox
      initRevBV4_ok presentTable_ok presentTotalGates presentTotalOutputs presentTotal_check⟩

end LwcSbox
