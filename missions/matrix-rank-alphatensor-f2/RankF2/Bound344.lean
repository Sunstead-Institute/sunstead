import RankF2.Common
import RankF2.Cert344

namespace B334
set_option maxRecDepth 200000
set_option maxHeartbeats 20000000

theorem cert344_correct : ∀ x < 12, ∀ y < 16, ∀ z < 12,
    entryN cert344 x y z = tgtShape 3 4 4 x y z := by
  decide +kernel

theorem bound344 : RankLE (mmT 3 4 4) score344 :=
  rankLE_of_certificate 3 4 4 cert344 rfl cert344_correct

end B334
