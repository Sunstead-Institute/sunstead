import LwcLinearXor.Spec
import LwcLinearXor.AsconSigma2Circuit

namespace LwcLinearXor

set_option maxRecDepth 200000
set_option maxHeartbeats 8000000

theorem asconSigma2_wf : wellFormedXor 64 asconSigma2Gates asconSigma2Outputs = true := by
  decide +kernel

theorem asconSigma2_len : asconSigma2Gates.length = asconSigma2Score := by
  decide +kernel

theorem asconSigma2_check : checkLinearCircuit 64 asconSigma2Rows asconSigma2Gates asconSigma2Outputs = true := by
  decide +kernel

theorem ascon_sigma2_xor_bound : ValidXorCircuit 64 asconSigma2_64 asconSigma2Score :=
  ⟨asconSigma2Gates, asconSigma2Outputs, asconSigma2_wf, asconSigma2_len,
    evalXorCircuit_eq_asconSigma2_of_check asconSigma2Gates asconSigma2Outputs asconSigma2_check⟩

end LwcLinearXor
