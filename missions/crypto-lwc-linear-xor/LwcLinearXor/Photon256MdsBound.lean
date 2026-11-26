import LwcLinearXor.Spec
import LwcLinearXor.Photon256MdsCircuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem photon256Mds_wf : wellFormedXor 32 photon256MdsGates photon256MdsOutputs = true := by
  decide +kernel

theorem photon256Mds_len : photon256MdsGates.length = photon256MdsScore := by
  decide +kernel

theorem photon256Mds_check : checkLinearCircuit 32 photon256MdsRows photon256MdsGates photon256MdsOutputs = true := by
  decide +kernel

theorem photon256_mds_xor_bound : ValidXorCircuit 32 photon256Mds32 photon256MdsScore :=
  ⟨photon256MdsGates, photon256MdsOutputs, photon256Mds_wf, photon256Mds_len,
    evalXorCircuit_eq_photon256Mds_of_check photon256MdsGates photon256MdsOutputs photon256Mds_check⟩

end LwcLinearXor
