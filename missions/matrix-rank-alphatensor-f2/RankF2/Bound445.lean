import RankF2.Common
import RankF2.Cert445

namespace B334

/-- All 320 packed rows of the submitted table match ⟨4,4,5⟩ (one kernel evaluation). -/
theorem cert445_rows : rowsOK 4 4 5 cert445 = true := by
  decide +kernel

theorem cert445_correct : ∀ x < 16, ∀ y < 20, ∀ z < 20,
    entryN cert445 x y z = tgtShape 4 4 5 x y z :=
  entries_of_rowsOK 4 4 5 cert445 cert445_rows

theorem bound445 : RankLE (mmT 4 4 5) score445 :=
  rankLE_of_certificate 4 4 5 cert445 rfl cert445_correct

end B334
