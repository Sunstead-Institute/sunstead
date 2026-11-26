import CryptoLinearXor.Spec
import CryptoLinearXor.CamelliaPCircuit

namespace CryptoLinearXor

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem camelliaP_wellFormed : wellFormedXor 8 camelliaPGates camelliaPOutputs = true := by
  decide +kernel

theorem camelliaP_length : camelliaPGates.length = camelliaPScore := by
  decide +kernel

theorem camelliaP_check :
    checkLinearCircuit 8 camelliaPRows camelliaPGates camelliaPOutputs = true := by
  decide +kernel

/-- The submitted straight-line XOR circuit certifies `ValidXorCircuit 8 camelliaP8 camelliaPScore`. -/
theorem camellia_p_bound : ValidXorCircuit 8 camelliaP8 camelliaPScore :=
  ⟨camelliaPGates, camelliaPOutputs, camelliaP_wellFormed, camelliaP_length,
    evalXorCircuit_eq_camelliaP8_of_check camelliaPGates camelliaPOutputs camelliaP_check⟩

end CryptoLinearXor
