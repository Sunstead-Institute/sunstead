import RankF2.Common
import RankF2.Cert334

namespace B334

/-- All 108 packed rows of the submitted table match ⟨3,3,4⟩ (one kernel evaluation). -/
theorem cert334_rows : rowsOK 3 3 4 cert334 = true := by
  decide +kernel

theorem cert334_correct : ∀ x < 9, ∀ y < 12, ∀ z < 12,
    entryN cert334 x y z = tgtShape 3 3 4 x y z :=
  entries_of_rowsOK 3 3 4 cert334 cert334_rows

theorem bound334 : RankLE (mmT 3 3 4) score334 :=
  rankLE_of_certificate 3 3 4 cert334 rfl cert334_correct

end B334
