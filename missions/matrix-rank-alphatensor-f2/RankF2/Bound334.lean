import RankF2.Common
import RankF2.Cert334

namespace B334
set_option maxRecDepth 200000
set_option maxHeartbeats 20000000

theorem cert334_correct : ∀ x < 9, ∀ y < 12, ∀ z < 12,
    entryN cert334 x y z = tgtShape 3 3 4 x y z := by
  decide +kernel

theorem bound334 : RankLE (mmT 3 3 4) score334 :=
  rankLE_of_certificate 3 3 4 cert334 rfl cert334_correct

end B334
