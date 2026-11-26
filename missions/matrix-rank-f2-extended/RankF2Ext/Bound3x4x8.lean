import RankF2Ext.Spec
import RankF2Ext.Cert3x4x8

namespace RankF2Ext

set_option maxRecDepth 200000
set_option maxHeartbeats 16000000

theorem cert_3_4_8_len : cert_3_4_8.length = score_3_4_8 := by
  decide +kernel

theorem cert_3_4_8_valid : checkBrentF2 3 4 8 cert_3_4_8 = true := by
  decide +kernel

theorem bound_3_4_8 : RankLE 3 4 8 score_3_4_8 :=
  rankLE_of_checkBrentF2 3 4 8 cert_3_4_8 cert_3_4_8_len cert_3_4_8_valid

end RankF2Ext
