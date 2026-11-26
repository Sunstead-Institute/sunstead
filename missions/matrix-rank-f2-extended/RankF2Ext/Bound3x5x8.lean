import RankF2Ext.Spec
import RankF2Ext.Cert3x5x8

namespace RankF2Ext

set_option maxRecDepth 200000
set_option maxHeartbeats 16000000

theorem cert_3_5_8_len : cert_3_5_8.length = score_3_5_8 := by
  decide +kernel

theorem cert_3_5_8_valid : checkBrentF2 3 5 8 cert_3_5_8 = true := by
  decide +kernel

theorem bound_3_5_8 : RankLE 3 5 8 score_3_5_8 :=
  rankLE_of_checkBrentF2 3 5 8 cert_3_5_8 cert_3_5_8_len cert_3_5_8_valid

end RankF2Ext
