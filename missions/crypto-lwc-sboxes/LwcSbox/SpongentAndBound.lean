import LwcSbox.Spec
import LwcSbox.SpongentAndCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem spongentAnd_wf : wellFormed 4 spongentAndGates spongentAndOutputs = true := by
  decide +kernel

theorem spongentAnd_metric : andCount spongentAndGates = spongentAndScore := by
  decide +kernel

theorem spongentAnd_check : checkCircuitBV 4 initRevBV4 spongentTable spongentAndGates spongentAndOutputs = true := by
  decide +kernel

theorem spongent_and_gates_bound : ValidAndCircuit 4 spongentSbox spongentAndScore :=
  ⟨spongentAndGates, spongentAndOutputs, spongentAnd_wf, spongentAnd_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 spongentTable spongentSbox
      initRevBV4_ok spongentTable_ok spongentAndGates spongentAndOutputs spongentAnd_check⟩

end LwcSbox
