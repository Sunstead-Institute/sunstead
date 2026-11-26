import LwcSbox.Spec
import LwcSbox.GiftAndCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem giftAnd_wf : wellFormed 4 giftAndGates giftAndOutputs = true := by
  decide +kernel

theorem giftAnd_metric : andCount giftAndGates = giftAndScore := by
  decide +kernel

theorem giftAnd_check : checkCircuitBV 4 initRevBV4 giftTable giftAndGates giftAndOutputs = true := by
  decide +kernel

theorem gift_and_gates_bound : ValidAndCircuit 4 giftSbox giftAndScore :=
  ⟨giftAndGates, giftAndOutputs, giftAnd_wf, giftAnd_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 giftTable giftSbox
      initRevBV4_ok giftTable_ok giftAndGates giftAndOutputs giftAnd_check⟩

end LwcSbox
