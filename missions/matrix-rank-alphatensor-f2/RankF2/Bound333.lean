import RankF2.Common
import RankF2.Cert333

namespace B334

/-- All 81 packed rows of the submitted table match ⟨3,3,3⟩ (one kernel evaluation). -/
theorem cert333_rows : rowsOK 3 3 3 cert333 = true := by
  decide +kernel

theorem cert333_correct : ∀ x < 9, ∀ y < 9, ∀ z < 9,
    entryN cert333 x y z = tgtShape 3 3 3 x y z :=
  entries_of_rowsOK 3 3 3 cert333 cert333_rows

theorem bound333 : RankLE (mmT 3 3 3) score333 :=
  rankLE_of_certificate 3 3 3 cert333 rfl cert333_correct

end B334
