import LwcSbox.Spec
import LwcSbox.GiftTotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem giftTotal_wf : wellFormed 4 giftTotalGates giftTotalOutputs = true := by
  decide +kernel

theorem giftTotal_metric : giftTotalGates.length = giftTotalScore := by
  decide +kernel

theorem giftTotal_check : checkCircuitBV 4 initRevBV4 giftTable giftTotalGates giftTotalOutputs = true := by
  decide +kernel

theorem gift_total_gates_bound : ValidTotalCircuit 4 giftSbox giftTotalScore :=
  ⟨giftTotalGates, giftTotalOutputs, giftTotal_wf, giftTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 giftTable giftSbox
      initRevBV4_ok giftTable_ok giftTotalGates giftTotalOutputs giftTotal_check⟩

end LwcSbox
