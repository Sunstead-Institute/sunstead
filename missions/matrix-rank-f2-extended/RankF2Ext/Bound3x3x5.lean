import RankF2Ext.Spec
import RankF2Ext.Cert3x3x5

namespace RankF2Ext

set_option maxRecDepth 200000
set_option maxHeartbeats 16000000

theorem cert_3_3_5_len : cert_3_3_5.length = score_3_3_5 := by
  decide +kernel

theorem cert_3_3_5_valid : checkBrentF2 3 3 5 cert_3_3_5 = true := by
  decide +kernel

theorem bound_3_3_5 : RankLE 3 3 5 score_3_3_5 :=
  rankLE_of_checkBrentF2 3 3 5 cert_3_3_5 cert_3_3_5_len cert_3_3_5_valid

end RankF2Ext
