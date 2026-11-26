import LwcSbox.Spec
import LwcSbox.PresentAndCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem presentAnd_wf : wellFormed 4 presentAndGates presentAndOutputs = true := by
  decide +kernel

theorem presentAnd_metric : andCount presentAndGates = presentAndScore := by
  decide +kernel

theorem presentAnd_check : checkCircuitBV 4 initRevBV4 presentTable presentAndGates presentAndOutputs = true := by
  decide +kernel

theorem present_and_gates_bound : ValidAndCircuit 4 presentSbox presentAndScore :=
  ⟨presentAndGates, presentAndOutputs, presentAnd_wf, presentAnd_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 presentTable presentSbox
      initRevBV4_ok presentTable_ok presentAndGates presentAndOutputs presentAnd_check⟩

end LwcSbox
