import LwcSbox.Spec
import LwcSbox.Skinny8DepthCircuit

namespace LwcSbox

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem skinny8Depth_wf : wellFormed 8 skinny8DepthGates skinny8DepthOutputs = true := by
  decide +kernel

theorem skinny8Depth_metric : andDepth 8 skinny8DepthGates skinny8DepthOutputs = skinny8DepthScore := by
  decide +kernel

theorem skinny8Depth_check : checkCircuitBV 8 initRevBV8 skinny8Table skinny8DepthGates skinny8DepthOutputs = true := by
  decide +kernel

theorem skinny8_and_depth_bound : ValidAndDepthCircuit 8 skinny8Sbox skinny8DepthScore :=
  ⟨skinny8DepthGates, skinny8DepthOutputs, skinny8Depth_wf, skinny8Depth_metric,
    evalCircuit_eq_of_checkCircuitBV 8 initRevBV8 skinny8Table skinny8Sbox
      initRevBV8_ok skinny8Table_ok skinny8DepthGates skinny8DepthOutputs skinny8Depth_check⟩

end LwcSbox
