import SortDepth.Spec
import SortDepth.Layers11

namespace SortDepth

set_option maxRecDepth 100000
set_option maxHeartbeats 4000000

theorem wellFormed_11 : wellFormedLayers 11 layers11 = true := by
  decide +kernel

theorem length_11 : layers11.length = depth11 := by
  decide +kernel

theorem check_11 : checkSortLayers 11 layers11 = true := by
  decide +kernel

/-- The submitted parallel comparator network certifies `ValidParallelSortingNetwork 11 depth11`. -/
theorem bound_11 : ValidParallelSortingNetwork 11 depth11 :=
  validParallelSortingNetwork_of_check 11 depth11 layers11 wellFormed_11 length_11 check_11

end SortDepth
