import LwcLinearXor.Spec
import LwcLinearXor.Clyde128LboxCircuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem clyde128Lbox_wf : wellFormedXor 64 clyde128LboxGates clyde128LboxOutputs = true := by
  decide +kernel

theorem clyde128Lbox_len : clyde128LboxGates.length = clyde128LboxScore := by
  decide +kernel

theorem clyde128Lbox_check : checkLinearCircuit 64 clyde128LboxRows clyde128LboxGates clyde128LboxOutputs = true := by
  decide +kernel

theorem clyde128_lbox_xor_bound : ValidXorCircuit 64 clyde128Lbox64 clyde128LboxScore :=
  ⟨clyde128LboxGates, clyde128LboxOutputs, clyde128Lbox_wf, clyde128Lbox_len,
    evalXorCircuit_eq_clyde128Lbox_of_check clyde128LboxGates clyde128LboxOutputs clyde128Lbox_check⟩

end LwcLinearXor
