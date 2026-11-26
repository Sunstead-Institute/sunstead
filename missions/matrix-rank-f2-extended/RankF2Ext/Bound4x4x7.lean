import RankF2Ext.Spec
import RankF2Ext.Cert4x4x7

namespace RankF2Ext

set_option maxRecDepth 200000
set_option maxHeartbeats 16000000

theorem cert_4_4_7_len : cert_4_4_7.length = score_4_4_7 := by
  decide +kernel

theorem cert_4_4_7_valid : checkBrentF2 4 4 7 cert_4_4_7 = true := by
  decide +kernel

theorem bound_4_4_7 : RankLE 4 4 7 score_4_4_7 :=
  rankLE_of_checkBrentF2 4 4 7 cert_4_4_7 cert_4_4_7_len cert_4_4_7_valid

end RankF2Ext
