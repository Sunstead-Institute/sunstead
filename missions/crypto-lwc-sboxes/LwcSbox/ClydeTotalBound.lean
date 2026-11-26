import LwcSbox.Spec
import LwcSbox.ClydeTotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem clydeTotal_wf : wellFormed 4 clydeTotalGates clydeTotalOutputs = true := by
  decide +kernel

theorem clydeTotal_metric : clydeTotalGates.length = clydeTotalScore := by
  decide +kernel

theorem clydeTotal_check : checkCircuitBV 4 initRevBV4 clydeTable clydeTotalGates clydeTotalOutputs = true := by
  decide +kernel

theorem clyde_total_gates_bound : ValidTotalCircuit 4 clydeSbox clydeTotalScore :=
  ⟨clydeTotalGates, clydeTotalOutputs, clydeTotal_wf, clydeTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 clydeTable clydeSbox
      initRevBV4_ok clydeTable_ok clydeTotalGates clydeTotalOutputs clydeTotal_check⟩

end LwcSbox
