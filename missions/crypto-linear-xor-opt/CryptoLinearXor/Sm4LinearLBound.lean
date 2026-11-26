import CryptoLinearXor.Spec
import CryptoLinearXor.Sm4LinearLCircuit

namespace CryptoLinearXor

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem sm4LinearL_wellFormed : wellFormedXor 32 sm4LinearLGates sm4LinearLOutputs = true := by
  decide +kernel

theorem sm4LinearL_length : sm4LinearLGates.length = sm4LinearLScore := by
  decide +kernel

theorem sm4LinearL_check :
    checkLinearCircuit 32 sm4LinearLRows sm4LinearLGates sm4LinearLOutputs = true := by
  decide +kernel

/-- The submitted straight-line XOR circuit certifies `ValidXorCircuit 32 sm4LinearL32 sm4LinearLScore`. -/
theorem sm4_linear_l_bound : ValidXorCircuit 32 sm4LinearL32 sm4LinearLScore :=
  ⟨sm4LinearLGates, sm4LinearLOutputs, sm4LinearL_wellFormed, sm4LinearL_length,
    evalXorCircuit_eq_sm4LinearL32_of_check sm4LinearLGates sm4LinearLOutputs sm4LinearL_check⟩

end CryptoLinearXor
