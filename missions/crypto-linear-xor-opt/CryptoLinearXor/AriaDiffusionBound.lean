import CryptoLinearXor.Spec
import CryptoLinearXor.AriaDiffusionCircuit

namespace CryptoLinearXor

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem ariaDiffusion_wellFormed : wellFormedXor 16 ariaDiffusionGates ariaDiffusionOutputs = true := by
  decide +kernel

theorem ariaDiffusion_length : ariaDiffusionGates.length = ariaDiffusionScore := by
  decide +kernel

theorem ariaDiffusion_check :
    checkLinearCircuit 16 ariaDiffusionRows ariaDiffusionGates ariaDiffusionOutputs = true := by
  decide +kernel

/-- The submitted straight-line XOR circuit certifies `ValidXorCircuit 16 ariaDiffusion16 ariaDiffusionScore`. -/
theorem aria_diffusion_bound : ValidXorCircuit 16 ariaDiffusion16 ariaDiffusionScore :=
  ⟨ariaDiffusionGates, ariaDiffusionOutputs, ariaDiffusion_wellFormed, ariaDiffusion_length,
    evalXorCircuit_eq_ariaDiffusion16_of_check ariaDiffusionGates ariaDiffusionOutputs ariaDiffusion_check⟩

end CryptoLinearXor
