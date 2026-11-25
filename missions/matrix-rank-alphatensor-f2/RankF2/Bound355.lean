import RankF2.Common
import RankF2.Cert355

namespace B334
set_option maxRecDepth 200000
set_option maxHeartbeats 20000000

theorem cert355_correct : ∀ x < 15, ∀ y < 25, ∀ z < 15,
    entryN cert355 x y z = tgtShape 3 5 5 x y z := by
  decide +kernel

theorem bound355 : RankLE (mmT 3 5 5) score355 :=
  rankLE_of_certificate 3 5 5 cert355 rfl cert355_correct

end B334
