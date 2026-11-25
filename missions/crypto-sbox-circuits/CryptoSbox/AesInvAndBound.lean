import CryptoSbox.Spec
import CryptoSbox.AesInvAndCircuit

namespace CryptoSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem aesInvAnd_wellFormed : wellFormed aesInvAndGates aesInvAndOutputs = true := by
  decide +kernel

theorem aesInvAnd_andCount : andCount aesInvAndGates = aesInvAndScore := by
  decide +kernel

theorem aesInvAnd_check : checkCircuit256 aesInvTable256 aesInvAndGates aesInvAndOutputs = true := by
  decide +kernel

/-- The submitted straight-line circuit certifies `ValidAndCircuit aesInvSbox aesInvAndScore`. -/
theorem aes_inv_and_bound : ValidAndCircuit aesInvSbox aesInvAndScore :=
  ⟨aesInvAndGates, aesInvAndOutputs, aesInvAnd_wellFormed, aesInvAnd_andCount,
    evalCircuit_eq_aesInvSbox_of_checkCircuit256 aesInvAndGates aesInvAndOutputs aesInvAnd_check⟩

end CryptoSbox
