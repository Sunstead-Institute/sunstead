import CryptoLinearXor.Spec
import CryptoLinearXor.AesInvMixColumnsCircuit

namespace CryptoLinearXor

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem aesInvMixColumns_wellFormed : wellFormedXor 32 aesInvMixColumnsGates aesInvMixColumnsOutputs = true := by
  decide +kernel

theorem aesInvMixColumns_length : aesInvMixColumnsGates.length = aesInvMixColumnsScore := by
  decide +kernel

theorem aesInvMixColumns_check :
    checkLinearCircuit 32 aesInvMixColumnsRows aesInvMixColumnsGates aesInvMixColumnsOutputs = true := by
  decide +kernel

/-- The submitted straight-line XOR circuit certifies `ValidXorCircuit 32 aesInvMixColumns32 aesInvMixColumnsScore`. -/
theorem aes_invmixcolumns_bound : ValidXorCircuit 32 aesInvMixColumns32 aesInvMixColumnsScore :=
  ⟨aesInvMixColumnsGates, aesInvMixColumnsOutputs, aesInvMixColumns_wellFormed, aesInvMixColumns_length,
    evalXorCircuit_eq_aesInvMixColumns32_of_check aesInvMixColumnsGates aesInvMixColumnsOutputs aesInvMixColumns_check⟩

end CryptoLinearXor
