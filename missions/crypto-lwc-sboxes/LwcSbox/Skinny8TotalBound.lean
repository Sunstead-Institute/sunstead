import LwcSbox.Spec
import LwcSbox.Skinny8TotalCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem skinny8Total_wf : wellFormed 8 skinny8TotalGates skinny8TotalOutputs = true := by
  decide +kernel

theorem skinny8Total_metric : skinny8TotalGates.length = skinny8TotalScore := by
  decide +kernel

theorem skinny8Total_check : checkCircuitBV 8 initRevBV8 skinny8Table skinny8TotalGates skinny8TotalOutputs = true := by
  decide +kernel

theorem skinny8_total_gates_bound : ValidTotalCircuit 8 skinny8Sbox skinny8TotalScore :=
  ⟨skinny8TotalGates, skinny8TotalOutputs, skinny8Total_wf, skinny8Total_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 skinny8Table skinny8Sbox
      initRevBV8_ok skinny8Table_ok skinny8TotalGates skinny8TotalOutputs skinny8Total_check⟩

end LwcSbox
