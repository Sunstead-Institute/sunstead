import RankF2.Common
import RankF2.Cert333

namespace B334
set_option maxRecDepth 200000
set_option maxHeartbeats 20000000

theorem cert333_correct : ∀ x < 9, ∀ y < 9, ∀ z < 9,
    entryN cert333 x y z = tgtShape 3 3 3 x y z := by
  decide +kernel

theorem bound333 : RankLE (mmT 3 3 3) score333 :=
  rankLE_of_certificate 3 3 3 cert333 rfl cert333_correct

end B334
