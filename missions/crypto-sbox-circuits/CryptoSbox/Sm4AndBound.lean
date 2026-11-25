import CryptoSbox.Spec
import CryptoSbox.Sm4AndCircuit

namespace CryptoSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem sm4And_wellFormed : wellFormed sm4AndGates sm4AndOutputs = true := by
  decide +kernel

theorem sm4And_andCount : andCount sm4AndGates = sm4AndScore := by
  decide +kernel

theorem sm4And_check : checkCircuit256 sm4Table256 sm4AndGates sm4AndOutputs = true := by
  decide +kernel

/-- The submitted straight-line circuit certifies `ValidAndCircuit sm4Sbox sm4AndScore`. -/
theorem sm4_and_bound : ValidAndCircuit sm4Sbox sm4AndScore :=
  ⟨sm4AndGates, sm4AndOutputs, sm4And_wellFormed, sm4And_andCount,
    evalCircuit_eq_sm4Sbox_of_checkCircuit256 sm4AndGates sm4AndOutputs sm4And_check⟩

end CryptoSbox
