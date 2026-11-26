import LwcSbox.Spec
import LwcSbox.SpongentTotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem spongentTotal_wf : wellFormed 4 spongentTotalGates spongentTotalOutputs = true := by
  decide +kernel

theorem spongentTotal_metric : spongentTotalGates.length = spongentTotalScore := by
  decide +kernel

theorem spongentTotal_check : checkCircuitBV 4 initRevBV4 spongentTable spongentTotalGates spongentTotalOutputs = true := by
  decide +kernel

theorem spongent_total_gates_bound : ValidTotalCircuit 4 spongentSbox spongentTotalScore :=
  ⟨spongentTotalGates, spongentTotalOutputs, spongentTotal_wf, spongentTotal_metric,
    evalCircuit_eq_of_checkCircuitBV 4 initRevBV4 spongentTable spongentSbox
      initRevBV4_ok spongentTable_ok spongentTotalGates spongentTotalOutputs spongentTotal_check⟩

end LwcSbox
