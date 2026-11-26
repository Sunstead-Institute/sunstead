import LwcSbox.Spec
import LwcSbox.AsconTotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem asconTotal_wf : wellFormed 5 asconTotalGates asconTotalOutputs = true := by
  decide +kernel

theorem asconTotal_metric : asconTotalGates.length = asconTotalScore := by
  decide +kernel

theorem asconTotal_check : checkCircuitBV 5 initRevBV5 asconTable asconTotalGates asconTotalOutputs = true := by
  decide +kernel

theorem ascon_total_gates_bound : ValidTotalCircuit 5 asconSbox asconTotalScore :=
  ⟨asconTotalGates, asconTotalOutputs, asconTotal_wf, asconTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 5 initRevBV5 asconTable asconSbox
      initRevBV5_ok asconTable_ok asconTotalGates asconTotalOutputs asconTotal_check⟩

end LwcSbox
