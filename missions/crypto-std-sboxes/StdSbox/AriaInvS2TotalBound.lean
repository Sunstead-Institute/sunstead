import StdSbox.Spec
import StdSbox.AriaInvS2TotalCircuit

namespace StdSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem ariaInvS2Total_wf : wellFormed 8 ariaInvS2TotalGates ariaInvS2TotalOutputs = true := by
  decide +kernel

theorem ariaInvS2Total_metric : ariaInvS2TotalGates.length = ariaInvS2TotalScore := by
  decide +kernel

theorem ariaInvS2Total_check : checkCircuitBV 8 initRevBV8 ariaInvS2Table ariaInvS2TotalGates ariaInvS2TotalOutputs = true := by
  decide +kernel

theorem aria_invs2_total_gates_bound : ValidTotalCircuit 8 ariaInvS2Sbox ariaInvS2TotalScore :=
  ⟨ariaInvS2TotalGates, ariaInvS2TotalOutputs, ariaInvS2Total_wf, ariaInvS2Total_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 ariaInvS2Table ariaInvS2Sbox
      initRevBV8_ok ariaInvS2Table_ok ariaInvS2TotalGates ariaInvS2TotalOutputs ariaInvS2Total_check⟩

end StdSbox
