import CryptoSbox.Spec
import CryptoSbox.CamelliaAndCircuit

namespace CryptoSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem camelliaAnd_wellFormed : wellFormed camelliaAndGates camelliaAndOutputs = true := by
  decide +kernel

theorem camelliaAnd_andCount : andCount camelliaAndGates = camelliaAndScore := by
  decide +kernel

theorem camelliaAnd_check : checkCircuit256 camelliaTable256 camelliaAndGates camelliaAndOutputs = true := by
  decide +kernel

/-- The submitted straight-line circuit certifies `ValidAndCircuit camelliaSbox1 camelliaAndScore`. -/
theorem camellia_and_bound : ValidAndCircuit camelliaSbox1 camelliaAndScore :=
  ⟨camelliaAndGates, camelliaAndOutputs, camelliaAnd_wellFormed, camelliaAnd_andCount,
    evalCircuit_eq_camelliaSbox1_of_checkCircuit256 camelliaAndGates camelliaAndOutputs camelliaAnd_check⟩

end CryptoSbox
