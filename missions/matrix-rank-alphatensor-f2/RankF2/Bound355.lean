import RankF2.Common
import RankF2.Cert355

namespace B334

/-- All 375 packed rows of the submitted table match ⟨3,5,5⟩ (one kernel evaluation). -/
theorem cert355_rows : rowsOK 3 5 5 cert355 = true := by
  decide +kernel

theorem cert355_correct : ∀ x < 15, ∀ y < 25, ∀ z < 15,
    entryN cert355 x y z = tgtShape 3 5 5 x y z :=
  entries_of_rowsOK 3 5 5 cert355 cert355_rows

theorem bound355 : RankLE (mmT 3 5 5) score355 :=
  rankLE_of_certificate 3 5 5 cert355 rfl cert355_correct

end B334
