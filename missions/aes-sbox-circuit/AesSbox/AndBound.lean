import AesSbox.Spec
import AesSbox.AndCircuit

namespace AesSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem and_wellFormed : wellFormed andGates andOutputs = true := by
  decide +kernel

theorem and_count : andCount andGates = andScore := by
  decide +kernel

theorem and_check : checkCircuit256 andGates andOutputs = true := by
  decide +kernel

/-- The submitted straight-line circuit certifies `ValidAndCircuit andScore`. -/
theorem and_bound : ValidAndCircuit andScore :=
  ⟨andGates, andOutputs, and_wellFormed, and_count,
    evalCircuit_eq_aesSbox_of_checkCircuit256 andGates andOutputs and_check⟩

end AesSbox
