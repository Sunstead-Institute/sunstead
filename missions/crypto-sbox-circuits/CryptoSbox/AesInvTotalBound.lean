import CryptoSbox.Spec
import CryptoSbox.AesInvTotalCircuit

namespace CryptoSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem aesInvTotal_wellFormed : wellFormed aesInvTotalGates aesInvTotalOutputs = true := by
  decide +kernel

theorem aesInvTotal_length : aesInvTotalGates.length = aesInvTotalScore := by
  decide +kernel

theorem aesInvTotal_check : checkCircuit256 aesInvTable256 aesInvTotalGates aesInvTotalOutputs = true := by
  decide +kernel

/-- The submitted straight-line circuit certifies `ValidTotalCircuit aesInvSbox aesInvTotalScore`. -/
theorem aes_inv_total_bound : ValidTotalCircuit aesInvSbox aesInvTotalScore :=
  ⟨aesInvTotalGates, aesInvTotalOutputs, aesInvTotal_wellFormed, aesInvTotal_length,
    evalCircuit_eq_aesInvSbox_of_checkCircuit256 aesInvTotalGates aesInvTotalOutputs aesInvTotal_check⟩

end CryptoSbox
