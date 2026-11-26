import StdSbox.Spec
import StdSbox.AriaInvS2AndCircuit

namespace StdSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem ariaInvS2And_wf : wellFormed 8 ariaInvS2AndGates ariaInvS2AndOutputs = true := by
  decide +kernel

theorem ariaInvS2And_metric : andCount ariaInvS2AndGates = ariaInvS2AndScore := by
  decide +kernel

theorem ariaInvS2And_check : checkCircuitBV 8 initRevBV8 ariaInvS2Table ariaInvS2AndGates ariaInvS2AndOutputs = true := by
  decide +kernel

theorem aria_invs2_and_gates_bound : ValidAndCircuit 8 ariaInvS2Sbox ariaInvS2AndScore :=
  ⟨ariaInvS2AndGates, ariaInvS2AndOutputs, ariaInvS2And_wf, ariaInvS2And_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 ariaInvS2Table ariaInvS2Sbox
      initRevBV8_ok ariaInvS2Table_ok ariaInvS2AndGates ariaInvS2AndOutputs ariaInvS2And_check⟩

end StdSbox
