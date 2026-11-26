import StdSbox.Spec
import StdSbox.AriaS2AndCircuit

namespace StdSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem ariaS2And_wf : wellFormed 8 ariaS2AndGates ariaS2AndOutputs = true := by
  decide +kernel

theorem ariaS2And_metric : andCount ariaS2AndGates = ariaS2AndScore := by
  decide +kernel

theorem ariaS2And_check : checkCircuitBV 8 initRevBV8 ariaS2Table ariaS2AndGates ariaS2AndOutputs = true := by
  decide +kernel

theorem aria_s2_and_gates_bound : ValidAndCircuit 8 ariaS2Sbox ariaS2AndScore :=
  ⟨ariaS2AndGates, ariaS2AndOutputs, ariaS2And_wf, ariaS2And_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 ariaS2Table ariaS2Sbox
      initRevBV8_ok ariaS2Table_ok ariaS2AndGates ariaS2AndOutputs ariaS2And_check⟩

end StdSbox
