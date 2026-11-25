import AesSbox.Spec
import AesSbox.TotalCircuit

namespace AesSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem total_wellFormed : wellFormed totalGates totalOutputs = true := by
  decide +kernel

theorem total_length : totalGates.length = totalScore := by
  decide +kernel

theorem total_check : checkCircuit256 totalGates totalOutputs = true := by
  decide +kernel

/-- The submitted straight-line circuit certifies `ValidTotalCircuit totalScore`. -/
theorem total_bound : ValidTotalCircuit totalScore :=
  ⟨totalGates, totalOutputs, total_wellFormed, total_length,
    evalCircuit_eq_aesSbox_of_checkCircuit256 totalGates totalOutputs total_check⟩

end AesSbox
