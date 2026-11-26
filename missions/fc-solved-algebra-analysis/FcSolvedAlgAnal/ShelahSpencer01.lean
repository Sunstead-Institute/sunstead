/-
Upstream source: https://github.com/google-deepmind/formal-conjectures/blob/5bd8bfb9def462c19a87d2d275af3db3341dc727/FormalConjectures/Paper/ShelahSpencerZeroOneLaw.lean#L60-L68
Upstream category: research solved | AMS: 3, 5
License: Apache-2.0 (The Formal Conjectures Authors)
-/
import FcSolvedAlgAnal.Spec

namespace FcSolvedAlgAnal.ShelahSpencer01

open FirstOrder Filter MeasureTheory Topology

theorem zeroOne_irrational
   (α : ℝ) (hα : 0 < α ∧ α < 1) (hirr : Irrational α) (φ : Language.graph.Sentence) :
   Tendsto (fun n =>
     sparseRandomGraph n α hα.1
       {G | @Language.Sentence.Realize Language.graph (Fin n) G.structure φ}) atTop (𝓝 0) ∨
   Tendsto (fun n =>
     sparseRandomGraph n α hα.1
       {G | @Language.Sentence.Realize Language.graph (Fin n) G.structure φ}) atTop (𝓝 1) := by
  sorry

end FcSolvedAlgAnal.ShelahSpencer01
