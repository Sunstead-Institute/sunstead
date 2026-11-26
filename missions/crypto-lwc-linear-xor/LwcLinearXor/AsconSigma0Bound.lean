import LwcLinearXor.Spec
import LwcLinearXor.AsconSigma0Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem asconSigma0_wf : wellFormedXor 64 asconSigma0Gates asconSigma0Outputs = true := by
  decide +kernel

theorem asconSigma0_len : asconSigma0Gates.length = asconSigma0Score := by
  decide +kernel

theorem asconSigma0_check : checkLinearCircuit 64 asconSigma0Rows asconSigma0Gates asconSigma0Outputs = true := by
  decide +kernel

theorem ascon_sigma0_xor_bound : ValidXorCircuit 64 asconSigma0_64 asconSigma0Score :=
  ⟨asconSigma0Gates, asconSigma0Outputs, asconSigma0_wf, asconSigma0_len,
    evalXorCircuit_eq_asconSigma0_of_check asconSigma0Gates asconSigma0Outputs asconSigma0_check⟩

end LwcLinearXor
