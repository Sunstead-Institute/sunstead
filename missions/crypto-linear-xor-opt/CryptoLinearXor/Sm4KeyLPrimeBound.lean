import CryptoLinearXor.Spec
import CryptoLinearXor.Sm4KeyLPrimeCircuit

namespace CryptoLinearXor

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem sm4KeyLPrime_wellFormed : wellFormedXor 32 sm4KeyLPrimeGates sm4KeyLPrimeOutputs = true := by
  decide +kernel

theorem sm4KeyLPrime_length : sm4KeyLPrimeGates.length = sm4KeyLPrimeScore := by
  decide +kernel

theorem sm4KeyLPrime_check :
    checkLinearCircuit 32 sm4KeyLPrimeRows sm4KeyLPrimeGates sm4KeyLPrimeOutputs = true := by
  decide +kernel

/-- The submitted straight-line XOR circuit certifies `ValidXorCircuit 32 sm4KeyLPrime32 sm4KeyLPrimeScore`. -/
theorem sm4_key_lprime_bound : ValidXorCircuit 32 sm4KeyLPrime32 sm4KeyLPrimeScore :=
  ⟨sm4KeyLPrimeGates, sm4KeyLPrimeOutputs, sm4KeyLPrime_wellFormed, sm4KeyLPrime_length,
    evalXorCircuit_eq_sm4KeyLPrime32_of_check sm4KeyLPrimeGates sm4KeyLPrimeOutputs sm4KeyLPrime_check⟩

end CryptoLinearXor
