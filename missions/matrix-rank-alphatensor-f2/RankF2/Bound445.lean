import RankF2.Common
import RankF2.Cert445

namespace B334
set_option maxRecDepth 200000
set_option maxHeartbeats 20000000

theorem cert445_correct : ∀ x < 16, ∀ y < 20, ∀ z < 20,
    entryN cert445 x y z = tgtShape 4 4 5 x y z := by
  decide +kernel

theorem bound445 : RankLE (mmT 4 4 5) score445 :=
  rankLE_of_certificate 4 4 5 cert445 rfl cert445_correct

end B334
