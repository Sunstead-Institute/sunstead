import CryptoSbox.Spec
import CryptoSbox.Sm4TotalCircuit

namespace CryptoSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem sm4Total_wellFormed : wellFormed sm4TotalGates sm4TotalOutputs = true := by
  decide +kernel

theorem sm4Total_length : sm4TotalGates.length = sm4TotalScore := by
  decide +kernel

theorem sm4Total_check : checkCircuit256 sm4Table256 sm4TotalGates sm4TotalOutputs = true := by
  decide +kernel

/-- The submitted straight-line circuit certifies `ValidTotalCircuit sm4Sbox sm4TotalScore`. -/
theorem sm4_total_bound : ValidTotalCircuit sm4Sbox sm4TotalScore :=
  ⟨sm4TotalGates, sm4TotalOutputs, sm4Total_wellFormed, sm4Total_length,
    evalCircuit_eq_sm4Sbox_of_checkCircuit256 sm4TotalGates sm4TotalOutputs sm4Total_check⟩

end CryptoSbox
