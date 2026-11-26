import StdSbox.Spec
import StdSbox.AriaS2TotalCircuit

namespace StdSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem ariaS2Total_wf : wellFormed 8 ariaS2TotalGates ariaS2TotalOutputs = true := by
  decide +kernel

theorem ariaS2Total_metric : ariaS2TotalGates.length = ariaS2TotalScore := by
  decide +kernel

theorem ariaS2Total_check : checkCircuitBV 8 initRevBV8 ariaS2Table ariaS2TotalGates ariaS2TotalOutputs = true := by
  decide +kernel

theorem aria_s2_total_gates_bound : ValidTotalCircuit 8 ariaS2Sbox ariaS2TotalScore :=
  ⟨ariaS2TotalGates, ariaS2TotalOutputs, ariaS2Total_wf, ariaS2Total_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 ariaS2Table ariaS2Sbox
      initRevBV8_ok ariaS2Table_ok ariaS2TotalGates ariaS2TotalOutputs ariaS2Total_check⟩

end StdSbox
