import RankF2Ext.Spec
import RankF2Ext.Cert3x3x7

namespace RankF2Ext

set_option maxRecDepth 200000
set_option maxHeartbeats 16000000

theorem cert_3_3_7_len : cert_3_3_7.length = score_3_3_7 := by
  decide +kernel

theorem cert_3_3_7_valid : checkBrentF2 3 3 7 cert_3_3_7 = true := by
  decide +kernel

theorem bound_3_3_7 : RankLE 3 3 7 score_3_3_7 :=
  rankLE_of_checkBrentF2 3 3 7 cert_3_3_7 cert_3_3_7_len cert_3_3_7_valid

end RankF2Ext
