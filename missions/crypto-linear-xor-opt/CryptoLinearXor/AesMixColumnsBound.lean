import CryptoLinearXor.Spec
import CryptoLinearXor.AesMixColumnsCircuit

namespace CryptoLinearXor

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem aesMixColumns_wellFormed : wellFormedXor 32 aesMixColumnsGates aesMixColumnsOutputs = true := by
  decide +kernel

theorem aesMixColumns_length : aesMixColumnsGates.length = aesMixColumnsScore := by
  decide +kernel

theorem aesMixColumns_check :
    checkLinearCircuit 32 aesMixColumnsRows aesMixColumnsGates aesMixColumnsOutputs = true := by
  decide +kernel

/-- The submitted straight-line XOR circuit certifies `ValidXorCircuit 32 aesMixColumns32 aesMixColumnsScore`. -/
theorem aes_mixcolumns_bound : ValidXorCircuit 32 aesMixColumns32 aesMixColumnsScore :=
  ⟨aesMixColumnsGates, aesMixColumnsOutputs, aesMixColumns_wellFormed, aesMixColumns_length,
    evalXorCircuit_eq_aesMixColumns32_of_check aesMixColumnsGates aesMixColumnsOutputs aesMixColumns_check⟩

end CryptoLinearXor
