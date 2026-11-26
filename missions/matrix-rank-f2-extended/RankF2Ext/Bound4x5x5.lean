import RankF2Ext.Spec
import RankF2Ext.Cert4x5x5

namespace RankF2Ext

set_option maxRecDepth 200000
set_option maxHeartbeats 16000000

theorem cert_4_5_5_len : cert_4_5_5.length = score_4_5_5 := by
  decide +kernel

theorem cert_4_5_5_valid : checkBrentF2 4 5 5 cert_4_5_5 = true := by
  decide +kernel

theorem bound_4_5_5 : RankLE 4 5 5 score_4_5_5 :=
  rankLE_of_checkBrentF2 4 5 5 cert_4_5_5 cert_4_5_5_len cert_4_5_5_valid

end RankF2Ext
