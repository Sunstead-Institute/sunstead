import RankF2Ext.Spec
import RankF2Ext.Cert4x4x8

namespace RankF2Ext

set_option maxRecDepth 200000
set_option maxHeartbeats 16000000

theorem cert_4_4_8_len : cert_4_4_8.length = score_4_4_8 := by
  decide +kernel

theorem cert_4_4_8_valid : checkBrentF2 4 4 8 cert_4_4_8 = true := by
  decide +kernel

theorem bound_4_4_8 : RankLE 4 4 8 score_4_4_8 :=
  rankLE_of_checkBrentF2 4 4 8 cert_4_4_8 cert_4_4_8_len cert_4_4_8_valid

end RankF2Ext
