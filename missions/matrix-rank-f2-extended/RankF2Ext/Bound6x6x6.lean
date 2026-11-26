import RankF2Ext.Spec
import RankF2Ext.Cert6x6x6

namespace RankF2Ext

set_option maxRecDepth 200000
set_option maxHeartbeats 16000000

theorem cert_6_6_6_len : cert_6_6_6.length = score_6_6_6 := by
  decide +kernel

theorem cert_6_6_6_valid : checkBrentF2 6 6 6 cert_6_6_6 = true := by
  decide +kernel

theorem bound_6_6_6 : RankLE 6 6 6 score_6_6_6 :=
  rankLE_of_checkBrentF2 6 6 6 cert_6_6_6 cert_6_6_6_len cert_6_6_6_valid

end RankF2Ext
