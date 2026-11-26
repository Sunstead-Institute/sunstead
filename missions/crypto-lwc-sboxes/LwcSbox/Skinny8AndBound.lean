import LwcSbox.Spec
import LwcSbox.Skinny8AndCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem skinny8And_wf : wellFormed 8 skinny8AndGates skinny8AndOutputs = true := by
  decide +kernel

theorem skinny8And_metric : andCount skinny8AndGates = skinny8AndScore := by
  decide +kernel

theorem skinny8And_check : checkCircuitBV 8 initRevBV8 skinny8Table skinny8AndGates skinny8AndOutputs = true := by
  decide +kernel

theorem skinny8_and_gates_bound : ValidAndCircuit 8 skinny8Sbox skinny8AndScore :=
  ⟨skinny8AndGates, skinny8AndOutputs, skinny8And_wf, skinny8And_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 skinny8Table skinny8Sbox
      initRevBV8_ok skinny8Table_ok skinny8AndGates skinny8AndOutputs skinny8And_check⟩

end LwcSbox
