import RankF2.Common
import RankF2.Cert345

namespace B334

/-- All 240 packed rows of the submitted table match ⟨3,4,5⟩ (one kernel evaluation). -/
theorem cert345_rows : rowsOK 3 4 5 cert345 = true := by
  decide +kernel

theorem cert345_correct : ∀ x < 12, ∀ y < 20, ∀ z < 15,
    entryN cert345 x y z = tgtShape 3 4 5 x y z :=
  entries_of_rowsOK 3 4 5 cert345 cert345_rows

theorem bound345 : RankLE (mmT 3 4 5) score345 :=
  rankLE_of_certificate 3 4 5 cert345 rfl cert345_correct

end B334
