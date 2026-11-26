import LwcSbox.Spec
import LwcSbox.PyjamaskTotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem pyjamaskTotal_wf : wellFormed 4 pyjamaskTotalGates pyjamaskTotalOutputs = true := by
  decide +kernel

theorem pyjamaskTotal_metric : pyjamaskTotalGates.length = pyjamaskTotalScore := by
  decide +kernel

theorem pyjamaskTotal_check : checkCircuitBV 4 initRevBV4 pyjamaskTable pyjamaskTotalGates pyjamaskTotalOutputs = true := by
  decide +kernel

theorem pyjamask_total_gates_bound : ValidTotalCircuit 4 pyjamaskSbox pyjamaskTotalScore :=
  ⟨pyjamaskTotalGates, pyjamaskTotalOutputs, pyjamaskTotal_wf, pyjamaskTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 pyjamaskTable pyjamaskSbox
      initRevBV4_ok pyjamaskTable_ok pyjamaskTotalGates pyjamaskTotalOutputs pyjamaskTotal_check⟩

end LwcSbox
