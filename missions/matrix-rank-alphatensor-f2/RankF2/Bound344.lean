import RankF2.Common
import RankF2.Cert344

namespace B334

/-- All 192 packed rows of the submitted table match ⟨3,4,4⟩ (one kernel evaluation). -/
theorem cert344_rows : rowsOK 3 4 4 cert344 = true := by
  decide +kernel

theorem cert344_correct : ∀ x < 12, ∀ y < 16, ∀ z < 12,
    entryN cert344 x y z = tgtShape 3 4 4 x y z :=
  entries_of_rowsOK 3 4 4 cert344 cert344_rows

theorem bound344 : RankLE (mmT 3 4 4) score344 :=
  rankLE_of_certificate 3 4 4 cert344 rfl cert344_correct

end B334
