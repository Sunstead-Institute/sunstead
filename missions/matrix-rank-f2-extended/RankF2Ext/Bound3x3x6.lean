import RankF2Ext.Spec
import RankF2Ext.Cert3x3x6

namespace RankF2Ext

set_option maxRecDepth 200000
set_option maxHeartbeats 16000000

theorem cert_3_3_6_len : cert_3_3_6.length = score_3_3_6 := by
  decide +kernel

theorem cert_3_3_6_valid : checkBrentF2 3 3 6 cert_3_3_6 = true := by
  decide +kernel

theorem bound_3_3_6 : RankLE 3 3 6 score_3_3_6 :=
  rankLE_of_checkBrentF2 3 3 6 cert_3_3_6 cert_3_3_6_len cert_3_3_6_valid

end RankF2Ext
