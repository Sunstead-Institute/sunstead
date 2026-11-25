import RankF2.Common
import RankF2.Cert345

namespace B334
set_option maxRecDepth 200000
set_option maxHeartbeats 20000000

theorem cert345_correct : ∀ x < 12, ∀ y < 20, ∀ z < 15,
    entryN cert345 x y z = tgtShape 3 4 5 x y z := by
  decide +kernel

theorem bound345 : RankLE (mmT 3 4 5) score345 :=
  rankLE_of_certificate 3 4 5 cert345 rfl cert345_correct

end B334
