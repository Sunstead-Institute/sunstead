#!/usr/bin/env python3
"""
Sunstead Lean 4.36.0 + Mathlib red-team suite: submissions that MUST be rejected,
plus honest controls (pure Lean, Mathlib `ring`/`norm_num`, and kernel hill-climb)
that MUST be accepted, run directly against `sunstead/verifier-lean4:v0.2`
(the same way the hub runs it) so the checks don't depend on the hub.

    ./scripts/build-verifiers.sh && python3 scripts/redteam.py            # Docker (default)
    python3 scripts/redteam.py --mission __synthetic_pure_lean__          # one mission
    sudo -E python3 scripts/redteam.py --local                            # no Docker

Exit code 0 only if every case gets the expected verdict.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MISSIONS = os.path.join(ROOT, "missions")
DEFAULT_IMAGE = "sunstead/verifier-lean4:v0.2"
V435_IMAGE = "sunstead/verifier-lean4-v4.35.0:v0.1"
V431_IMAGE = "sunstead/verifier-lean4-v4.31.0:v0.1"
IMAGES = {
    "arklib-near-capacity-primes": DEFAULT_IMAGE,
    "ieantn-chebyshev-kernel": DEFAULT_IMAGE,
    "ieantn-short-interval-primes": DEFAULT_IMAGE,
    "ieantn-zeta-foundations": DEFAULT_IMAGE,
    "ieantn-chebyshev-pipeline": DEFAULT_IMAGE,
    "ieantn-schoenfeld-chebyshev": DEFAULT_IMAGE,
    "ieantn-zero-free-regions": DEFAULT_IMAGE,
    "ieantn-zeta-logderiv-values": DEFAULT_IMAGE,
    "ieantn-buthe-prime-bounds": DEFAULT_IMAGE,
    "pnt-analytic-foundations": DEFAULT_IMAGE,
    "lnsym-aes-gcm-armv8": V435_IMAGE,
    "lnsym-gcm-gmult-armv8": V435_IMAGE,
    "curve25519-dalek": V431_IMAGE,
    "matrix-rank444-f2": DEFAULT_IMAGE,
    "matrix-rank-alphatensor-f2": DEFAULT_IMAGE,
    "aes-sbox-circuit": DEFAULT_IMAGE,
    "__synthetic_pure_lean__": DEFAULT_IMAGE,
    "__synthetic_mathlib__": DEFAULT_IMAGE,
    "__synthetic_hillclimb__": DEFAULT_IMAGE,
    "__synthetic_repo_snapshot__": DEFAULT_IMAGE,
    "__synthetic_cross_file_dag__": DEFAULT_IMAGE,
    "__synthetic_module_snapshot__": DEFAULT_IMAGE,
}

HONEST_DECODER = """import SyntheticPureLean.Spec

namespace SyntheticPureLean

theorem encode_injective_of_lossless {n k : Nat} (c : LosslessCompressor n k) :
    Injective c.encode := by
  intro a b h
  have h1 := congrArg c.decode h
  rw [c.left_inv, c.left_inv] at h1
  exact h1

end SyntheticPureLean
"""

# Synthetic in-memory zero-Mathlib pure-Lean fixture (formerly `onboarding-sandbox`)
# keeping fast pure-Lean attack and honest-control coverage intact after retiring
# the live sandbox mission.
SYNTHETIC_PURE_LEAN_TREE = {
    "lean-toolchain": "leanprover/lean4:v4.36.0\n",
    "lakefile.toml": (
        'name = "synthetic_pure_lean"\nversion = "0.1.0"\n\n'
        '[[lean_lib]]\nname = "SyntheticPureLean"\n'
    ),
    "SyntheticPureLean/Spec.lean": (
        "namespace SyntheticPureLean\n\n"
        "def Injective {α β : Type} (f : α → β) : Prop :=\n"
        "  ∀ a b, f a = f b → a = b\n\n"
        "def otpEnc {n : Nat} (m k : BitVec n) : BitVec n := m ^^^ k\n\n"
        "structure LosslessCompressor (n k : Nat) where\n"
        "  encode : Fin (2 ^ n) → Fin (2 ^ k)\n"
        "  decode : Fin (2 ^ k) → Fin (2 ^ n)\n"
        "  left_inv : ∀ x, decode (encode x) = x\n\n"
        "end SyntheticPureLean\n"
    ),
    "SyntheticPureLean/DecoderInjective.lean": (
        "import SyntheticPureLean.Spec\n\n"
        "namespace SyntheticPureLean\n\n"
        "theorem encode_injective_of_lossless {n k : Nat} (c : LosslessCompressor n k) :\n"
        "    Injective c.encode := by\n"
        "  sorry\n\n"
        "end SyntheticPureLean\n"
    ),
    "SyntheticPureLean/Pigeonhole.lean": (
        "import SyntheticPureLean.Spec\n\n"
        "namespace SyntheticPureLean\n\n"
        "theorem no_inj_lt :\n"
        "    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by\n"
        "  sorry\n\n"
        "end SyntheticPureLean\n"
    ),
    "verify": (
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "sys.path.insert(0, '/opt/sunstead')\n"
        "from sunstead_sandbox import emit, lean_verify\n"
        "TASKS = {\n"
        "  'decoder_injective': {\n"
        "    'module': 'SyntheticPureLean.DecoderInjective',\n"
        "    'theorem': 'SyntheticPureLean.encode_injective_of_lossless',\n"
        "    'statement': 'def decoder_injective : Prop := ∀ {n k : Nat} (c : SyntheticPureLean.LosslessCompressor n k), SyntheticPureLean.Injective c.encode',\n"
        "  },\n"
        "  'pigeonhole_fin': {\n"
        "    'module': 'SyntheticPureLean.Pigeonhole',\n"
        "    'theorem': 'SyntheticPureLean.no_inj_lt',\n"
        "    'statement': 'def pigeonhole_fin : Prop := ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ SyntheticPureLean.Injective f',\n"
        "  },\n"
        "}\n"
        "lean_verify(sys.argv[1], lib_root='SyntheticPureLean', frozen_files=['SyntheticPureLean/Spec.lean', 'lakefile.toml', 'lean-toolchain'], tasks=TASKS)\n"
    ),
}

# Synthetic in-memory Mathlib mission so CI proves honest Mathlib proofs (using
# `import Mathlib.Tactic` + `ring`) pass kernel replay without committing any
# spoiler solution to a live upstream research obligation.
SYNTHETIC_MATHLIB_TREE = {
    "lean-toolchain": "leanprover/lean4:v4.36.0\n",
    "lakefile.toml": (
        'name = "SyntheticMathlib"\nversion = "0.1.0"\n\n'
        '[[lean_lib]]\nname = "SyntheticMathlib"\n'
    ),
    "SyntheticMathlib/Spec.lean": (
        "import Mathlib.Data.Real.Basic\n\n"
        "namespace SyntheticMathlib\n"
        "def sqSum (a b : ℝ) : ℝ := (a + b) ^ 2\n"
        "end SyntheticMathlib\n"
    ),
    "SyntheticMathlib/Target.lean": (
        "import SyntheticMathlib.Spec\n"
        "import Mathlib.Tactic\n\n"
        "namespace SyntheticMathlib\n"
        "theorem sqSum_expand (a b : ℝ) : sqSum a b = a ^ 2 + 2 * a * b + b ^ 2 := by\n"
        "  unfold sqSum\n"
        "  ring\n"
        "end SyntheticMathlib\n"
    ),
    "verify": (
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "sys.path.insert(0, '/opt/sunstead')\n"
        "from sunstead_sandbox import emit, lean_verify\n"
        "TASKS = {\n"
        "  'sq_sum_expand': {\n"
        "    'module': 'SyntheticMathlib.Target',\n"
        "    'theorem': 'SyntheticMathlib.sqSum_expand',\n"
        "    'statement': 'def sq_sum_expand : Prop := ∀ (a b : ℝ), SyntheticMathlib.sqSum a b = a ^ 2 + 2 * a * b + b ^ 2',\n"
        "  }\n"
        "}\n"
        "lean_verify(sys.argv[1], lib_root='SyntheticMathlib', frozen_files=['SyntheticMathlib/Spec.lean', 'lakefile.toml', 'lean-toolchain'], tasks=TASKS, uses_mathlib=True, timeout_sec=120)\n"
    ),
}

# Synthetic hill-climb fixture to keep `score_const` kernel evaluation covered
# even while v1 has no toy Tier 2 demos active.
SYNTHETIC_HILLCLIMB_TREE = {
    "lean-toolchain": "leanprover/lean4:v4.36.0\n",
    "lakefile.toml": (
        'name = "SyntheticHill"\nversion = "0.1.0"\n\n'
        '[[lean_lib]]\nname = "SyntheticHill"\n'
    ),
    "SyntheticHill/Spec.lean": (
        "namespace SyntheticHill\n"
        "def loss (n : Nat) : Nat := 3 * n\n"
        "end SyntheticHill\n"
    ),
    "SyntheticHill/Bound.lean": (
        "import SyntheticHill.Spec\n\n"
        "namespace SyntheticHill\n"
        "def claimedFactor : Nat := 1000\n"
        "theorem bound : ∀ n : Nat, loss n ≤ claimedFactor * n := by\n"
        "  intro n; unfold loss claimedFactor; omega\n"
        "end SyntheticHill\n"
    ),
    "verify": (
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "sys.path.insert(0, '/opt/sunstead')\n"
        "from sunstead_sandbox import emit, lean_verify\n"
        "TASKS = {\n"
        "  'tighten_bound': {\n"
        "    'module': 'SyntheticHill.Bound',\n"
        "    'theorem': 'SyntheticHill.bound',\n"
        "    'score_const': 'SyntheticHill.claimedFactor',\n"
        "    'statement': 'def tighten_bound (C : Nat) : Prop := ∀ n : Nat, SyntheticHill.loss n ≤ C * n',\n"
        "    'label': 'factor {score}',\n"
        "  }\n"
        "}\n"
        "lean_verify(sys.argv[1], lib_root='SyntheticHill', frozen_files=['SyntheticHill/Spec.lean', 'lakefile.toml', 'lean-toolchain'], tasks=TASKS)\n"
    ),
}

# Synthetic repo-snapshot fixture exercising full upstream-snapshot verification
# (frozen sibling module `SnapLib/Core.lean`, local `abbrev` type dependency
# inside writable `SnapLib/Target.lean`, and kernel-type check against the
# pinned upstream `.olean` without any manual `SunsteadStatements` copy).
_SNAP_CORE = """namespace SnapLib
def secretFactor : Nat := 7
def scale (n : Nat) : Nat := secretFactor * n
theorem scale_zero : scale 0 = 0 := by
  simp [scale]
end SnapLib
"""

_SNAP_TARGET_SEED = """import SnapLib.Core

namespace SnapLib

abbrev targetScale (n : Nat) : Nat := scale n

theorem target_add (a b : Nat) : targetScale (a + b) = targetScale a + targetScale b := by
  sorry

theorem target_zero : targetScale 0 = 0 := by
  sorry

end SnapLib
"""

_SNAP_TARGET_HONEST = """import SnapLib.Core

namespace SnapLib

abbrev targetScale (n : Nat) : Nat := scale n

theorem target_add (a b : Nat) : targetScale (a + b) = targetScale a + targetScale b := by
  unfold targetScale scale secretFactor
  omega

theorem target_zero : targetScale 0 = 0 := by
  exact scale_zero

end SnapLib
"""

_SNAP_TARGET_ONLY_T2 = """import SnapLib.Core

namespace SnapLib

abbrev targetScale (n : Nat) : Nat := scale n

theorem target_add (a b : Nat) : targetScale (a + b) = targetScale a + targetScale b := by
  sorry

theorem target_zero : targetScale 0 = 0 := by
  exact scale_zero

end SnapLib
"""

SYNTHETIC_REPO_SNAPSHOT_TREE = {
    "lean-toolchain": "leanprover/lean4:v4.36.0\n",
    ".sunstead-frozen-snapshot/SnapLib/Core.lean": _SNAP_CORE,
    ".sunstead-frozen-snapshot/SnapLib/Target.lean": _SNAP_TARGET_SEED,
    "SnapLib/Core.lean": _SNAP_CORE,
    "SnapLib/Target.lean": _SNAP_TARGET_HONEST,
    "verify": (
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "sys.path.insert(0, '/opt/sunstead')\n"
        "from sunstead_sandbox import emit, lean_repo_snapshot_verify\n"
        "TASKS = {\n"
        "  'target_add': {\n"
        "    'module': 'SnapLib.Target',\n"
        "    'theorem': 'SnapLib.target_add',\n"
        "    'target_files': ['SnapLib/Target.lean'],\n"
        "  },\n"
        "  'target_zero': {\n"
        "    'module': 'SnapLib.Target',\n"
        "    'theorem': 'SnapLib.target_zero',\n"
        "    'target_files': ['SnapLib/Target.lean'],\n"
        "    'preserve_theorems': ['SnapLib.target_add'],\n"
        "  },\n"
        "}\n"
        "lean_repo_snapshot_verify(\n"
        "  sys.argv[1],\n"
        "  snapshot_id='__synthetic_repo_snapshot__',\n"
        "  frozen_files=['lean-toolchain'],\n"
        "  tasks=TASKS,\n"
        "  allowed_import_prefixes=['SnapLib', 'Init'],\n"
        "  uses_mathlib=False,\n"
        "  snapshot_source_dir='.sunstead-frozen-snapshot',\n"
        "  allow_other_sorries=(sys.argv[1] == 'target_zero'),\n"
        "  timeout_sec=120,\n"
        ")\n"
    ),
}

# Synthetic cross-file repo-snapshot DAG fixture exercising:
#   Base (pure dep) -> Part1 (Task 1) -> Bridge (frozen bridge dep) -> Part2 (Task 2)
# Mirrors curve25519-dalek's `Basic -> Edwards.Curve -> Edwards.Representation -> Ristretto.Representation`.
_CROSS_BASE = """namespace CrossLib
def baseVal : Nat := 3
end CrossLib
"""

_CROSS_PART1_SEED = """import CrossLib.Base

namespace CrossLib
def part1Val : Nat := baseVal + 1
theorem part1_ok : part1Val = 4 := by
  sorry
end CrossLib
"""

_CROSS_PART1_HONEST = """import CrossLib.Base

namespace CrossLib
def part1Val : Nat := baseVal + 1
theorem part1_ok : part1Val = 4 := rfl
end CrossLib
"""

_CROSS_BRIDGE = """import CrossLib.Part1

namespace CrossLib
def bridgeVal : Nat := part1Val + 1
theorem bridge_ok : bridgeVal = 5 := by
  simp [bridgeVal, part1_ok]
end CrossLib
"""

_CROSS_PART2_SEED = """import CrossLib.Part1
import CrossLib.Bridge

namespace CrossLib
def part2Pred (n : Nat) : Prop := n = bridgeVal
theorem part2_ok : part2Pred 5 := by
  sorry
end CrossLib
"""

_CROSS_PART2_HONEST = """import CrossLib.Part1
import CrossLib.Bridge

namespace CrossLib
def part2Pred (n : Nat) : Prop := n = bridgeVal
theorem part2_ok : part2Pred 5 := by
  unfold part2Pred
  exact bridge_ok.symm
end CrossLib
"""

SYNTHETIC_CROSS_FILE_DAG_TREE = {
    "lean-toolchain": "leanprover/lean4:v4.36.0\n",
    ".sunstead-frozen-snapshot/CrossLib/Base.lean": _CROSS_BASE,
    ".sunstead-frozen-snapshot/CrossLib/Part1.lean": _CROSS_PART1_SEED,
    ".sunstead-frozen-snapshot/CrossLib/Bridge.lean": _CROSS_BRIDGE,
    ".sunstead-frozen-snapshot/CrossLib/Part2.lean": _CROSS_PART2_SEED,
    "CrossLib/Part1.lean": _CROSS_PART1_HONEST,
    "CrossLib/Part2.lean": _CROSS_PART2_SEED,
    "verify": (
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "sys.path.insert(0, '/opt/sunstead')\n"
        "from sunstead_sandbox import emit, lean_repo_snapshot_verify\n"
        "TASKS = {\n"
        "  'part1_ok': {\n"
        "    'module': 'CrossLib.Part1',\n"
        "    'theorem': 'CrossLib.part1_ok',\n"
        "    'target_files': ['CrossLib/Part1.lean'],\n"
        "  },\n"
        "  'part2_ok': {\n"
        "    'module': 'CrossLib.Part2',\n"
        "    'theorem': 'CrossLib.part2_ok',\n"
        "    'target_files': ['CrossLib/Part2.lean'],\n"
        "    'prereq_modules': ['CrossLib.Part1'],\n"
        "    'bridge_modules': ['CrossLib.Bridge'],\n"
        "    'preserve_theorems': [{'module': 'CrossLib.Part1', 'theorem': 'CrossLib.part1_ok'}],\n"
        "  },\n"
        "}\n"
        "lean_repo_snapshot_verify(\n"
        "  sys.argv[1],\n"
        "  snapshot_id='__synthetic_cross_file_dag__',\n"
        "  frozen_files=['lean-toolchain'],\n"
        "  tasks=TASKS,\n"
        "  allowed_import_prefixes=['CrossLib', 'Init'],\n"
        "  uses_mathlib=False,\n"
        "  snapshot_source_dir='.sunstead-frozen-snapshot',\n"
        "  allow_other_sorries=(sys.argv[1] == 'part2_ok'),\n"
        "  timeout_sec=120,\n"
        ")\n"
    ),
}

# Synthetic Lean 4.36 `module`-system (`.olean.private`) repo-snapshot fixture
# exercising opt-in `allow_module_system=True` replay across a module-system
# dependency + target file, proving honest proofs pass while hidden private
# `sorryAx`, `private axiom`, `private import Lean`, and mutated local defs fail.
_MOD_CORE = """module

namespace ModSnap
@[expose] public def baseFactor : Nat := 11
@[expose] public def scaled (n : Nat) : Nat := baseFactor * n
public theorem scaled_zero : scaled 0 = 0 := by
  simp [scaled]
end ModSnap
"""

_MOD_TARGET_SEED = """module
public import ModSnap.Core

namespace ModSnap
@[expose] public def localScale (n : Nat) : Nat := scaled n

public theorem mod_add (a b : Nat) : localScale (a + b) = localScale a + localScale b := by
  sorry
end ModSnap
"""

_MOD_TARGET_HONEST = """module
public import ModSnap.Core

namespace ModSnap
@[expose] public def localScale (n : Nat) : Nat := scaled n

private theorem helper_add (a b : Nat) : baseFactor * (a + b) = baseFactor * a + baseFactor * b := by
  unfold baseFactor
  omega

public theorem mod_add (a b : Nat) : localScale (a + b) = localScale a + localScale b := by
  unfold localScale scaled
  exact helper_add a b
end ModSnap
"""

SYNTHETIC_MODULE_SNAPSHOT_TREE = {
    "lean-toolchain": "leanprover/lean4:v4.36.0\n",
    ".sunstead-frozen-snapshot/ModSnap/Core.lean": _MOD_CORE,
    ".sunstead-frozen-snapshot/ModSnap/Target.lean": _MOD_TARGET_SEED,
    "ModSnap/Core.lean": _MOD_CORE,
    "ModSnap/Target.lean": _MOD_TARGET_HONEST,
    "verify": (
        "#!/usr/bin/env python3\n"
        "import sys\n"
        "sys.path.insert(0, '/opt/sunstead')\n"
        "from sunstead_sandbox import emit, lean_repo_snapshot_verify\n"
        "TASKS = {\n"
        "  'mod_add': {\n"
        "    'module': 'ModSnap.Target',\n"
        "    'theorem': 'ModSnap.mod_add',\n"
        "    'target_files': ['ModSnap/Target.lean'],\n"
        "  },\n"
        "}\n"
        "lean_repo_snapshot_verify(\n"
        "  sys.argv[1],\n"
        "  snapshot_id='__synthetic_module_snapshot__',\n"
        "  frozen_files=['lean-toolchain'],\n"
        "  tasks=TASKS,\n"
        "  allowed_import_prefixes=['ModSnap', 'Init'],\n"
        "  uses_mathlib=False,\n"
        "  snapshot_source_dir='.sunstead-frozen-snapshot',\n"
        "  allow_module_system=True,\n"
        "  timeout_sec=120,\n"
        ")\n"
    ),
}

SYNTHETIC_TREES = {
    "__synthetic_pure_lean__": SYNTHETIC_PURE_LEAN_TREE,
    "__synthetic_mathlib__": SYNTHETIC_MATHLIB_TREE,
    "__synthetic_hillclimb__": SYNTHETIC_HILLCLIMB_TREE,
    "__synthetic_repo_snapshot__": SYNTHETIC_REPO_SNAPSHOT_TREE,
    "__synthetic_cross_file_dag__": SYNTHETIC_CROSS_FILE_DAG_TREE,
    "__synthetic_module_snapshot__": SYNTHETIC_MODULE_SNAPSHOT_TREE,
}

# Each case: (name, mission, task, {path: content}, expect_ok, expect_score_or_None, why)
with open(os.path.join(MISSIONS, "matrix-rank444-f2", "Rank444", "Certificate.lean"),
          encoding="utf-8") as f:
    RANK_BASELINE = f.read()

with open(os.path.join(MISSIONS, "aes-sbox-circuit", "AesSbox", "TotalCircuit.lean"),
          encoding="utf-8") as f:
    AES_TOTAL_BASELINE = f.read()

with open(os.path.join(MISSIONS, "aes-sbox-circuit", "AesSbox", "AndCircuit.lean"),
          encoding="utf-8") as f:
    AES_AND_BASELINE = f.read()

CASES = [
    ("rank444-wrong-score", "matrix-rank444-f2", "reduce_rank",
     {"Rank444/Certificate.lean": RANK_BASELINE.replace("Nat := 47", "Nat := 46", 1)},
     False, None, "score must equal the actual number of terms"),
    ("rank444-published-baseline", "matrix-rank444-f2", "reduce_rank",
     {}, True, 47, "published decomposition must kernel-replay at its table length"),
    ("rank444-invalid-table", "matrix-rank444-f2", "reduce_rank",
     {"Rank444/Certificate.lean": "def B334.score : Nat := 1\ndef certificate : List (Nat × Nat × Nat) := [(0, 0, 0)]\n"},
     False, None, "a shorter table must still compute the full multiplication tensor"),
    # --- AES S-box Boolean circuit hill-climb (`aes-sbox-circuit`) ---
    ("aes-sbox-total-baseline", "aes-sbox-circuit", "minimize_total_gates",
     {}, True, 130, "seed tower-field circuit must kernel-replay at 130 total gates"),
    ("aes-sbox-and-baseline", "aes-sbox-circuit", "minimize_and_gates",
     {}, True, 36, "seed tower-field circuit must kernel-replay at 36 AND gates"),
    ("aes-sbox-corrupted-output", "aes-sbox-circuit", "minimize_total_gates",
     {"AesSbox/TotalCircuit.lean": AES_TOTAL_BASELINE.replace("[132,", "[131,", 1)},
     False, None, "corrupted output wire must be rejected by the 256-input kernel check"),
    ("aes-sbox-and-corrupted-output", "aes-sbox-circuit", "minimize_and_gates",
     {"AesSbox/AndCircuit.lean": AES_AND_BASELINE.replace("[132,", "[131,", 1)},
     False, None, "corrupted AND-track output wire must be rejected by the 256-input kernel check"),
    ("aes-sbox-non-causal-wire", "aes-sbox-circuit", "minimize_total_gates",
     {"AesSbox/TotalCircuit.lean": AES_TOTAL_BASELINE.replace("[\n  (", "[\n  (0, 8, 0), --x\n  (", 1).replace(", --x\n  (", ",\n  (", 1).replace("Nat := 130", "Nat := 131", 1)},
     False, None, "non-causal/cyclic gate referencing wire 8 at gate 0 must be rejected by wellFormed"),
    ("aes-sbox-wrong-total-score", "aes-sbox-circuit", "minimize_total_gates",
     {"AesSbox/TotalCircuit.lean": AES_TOTAL_BASELINE.replace("Nat := 130", "Nat := 129", 1)},
     False, None, "claimed totalScore must equal totalGates.length"),
    ("aes-sbox-wrong-and-score", "aes-sbox-circuit", "minimize_and_gates",
     {"AesSbox/AndCircuit.lean": AES_AND_BASELINE.replace("Nat := 36", "Nat := 35", 1)},
     False, None, "claimed andScore must equal andCount andGates"),
    ("aes-sbox-code-injection", "aes-sbox-circuit", "minimize_total_gates",
     {"AesSbox/TotalCircuit.lean": AES_TOTAL_BASELINE + "\n#eval IO.println \"pwn\"\n"},
     False, None, "non-literal Lean code injection in circuit file must be rejected at lint"),
    # --- Pure Lean 4.36.0 attacks + honest control (`__synthetic_pure_lean__`) ---
    ("lean-honest-control", "__synthetic_pure_lean__", "decoder_injective",
     {"SyntheticPureLean/DecoderInjective.lean": HONEST_DECODER}, True, None,
     "honest pure-Lean proof must pass"),
    ("lean-sorry", "__synthetic_pure_lean__", "decoder_injective",
     {"SyntheticPureLean/DecoderInjective.lean": HONEST_DECODER.replace(
         "  intro a b h\n  have h1 := congrArg c.decode h\n  rw [c.left_inv, c.left_inv] at h1\n  exact h1\n",
         "  sorry\n")},
     False, None, "plain sorry"),
    ("lean-spoof-axiom-report", "__synthetic_pure_lean__", "pigeonhole_fin",
     {"SyntheticPureLean/Pigeonhole.lean": """import SyntheticPureLean.Spec
import Lean
open Lean Elab Command

namespace SyntheticPureLean
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  sorry
end SyntheticPureLean

elab_rules : command
  | `(#print axioms $_) => logInfo "'sunstead_audit' does not depend on any axioms"
"""},
     False, None, "an imported elaborator rewrote #print axioms output"),
    ("lean-eval-spoof", "__synthetic_pure_lean__", "pigeonhole_fin",
     {"SyntheticPureLean/Pigeonhole.lean": """import SyntheticPureLean.Spec
namespace SyntheticPureLean
axiom cheat : ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := cheat
end SyntheticPureLean
#eval IO.println "'sunstead_audit' does not depend on any axioms"
"""},
     False, None, "custom axiom plus printed fake axiom report"),
    ("lean-weakened-statement", "__synthetic_pure_lean__", "pigeonhole_fin",
     {"SyntheticPureLean/Pigeonhole.lean": """import SyntheticPureLean.Spec
namespace SyntheticPureLean
theorem no_inj_lt : ∀ {n m : Nat}, m < n → True := fun _ => trivial
end SyntheticPureLean
"""},
     False, None, "target theorem states something weaker than the frozen statement"),
    ("lean-notation-hijack", "__synthetic_pure_lean__", "pigeonhole_fin",
     {"SyntheticPureLean/Pigeonhole.lean": """import SyntheticPureLean.Spec
namespace SyntheticPureLean
macro_rules | `(¬ $p) => `(True)
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  intros; trivial
end SyntheticPureLean
"""},
     False, None, "redefining `¬` so an elaborated audit statement means something else"),
    ("lean-build-time-tamper", "__synthetic_pure_lean__", "pigeonhole_fin",
     {"SyntheticPureLean/Pigeonhole.lean": """import SyntheticPureLean.Spec
namespace SyntheticPureLean
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  sorry
end SyntheticPureLean
#eval (do
  let _ ← IO.Process.spawn { cmd := "sh", args := #["-c",
    "while true; do for f in /tmp/*/_SunsteadAudit.lean /tmp/verify_run/_SunsteadAudit.lean; do " ++
    "[ -f \\"$f\\" ] && printf '#eval IO.println \\"ok\\"\\\\n' > \\"$f\\"; done; sleep 0.05; done"] }
  pure () : IO Unit)
"""},
     False, None, "build-time #eval starts a process that rewrites the audit file"),
    ("lean-string-block-comment-hide", "__synthetic_pure_lean__", "decoder_injective",
     {"SyntheticPureLean/DecoderInjective.lean": HONEST_DECODER + """
def s1 : String := "/-"
#eval IO.println "escaped block comment lint"
def s2 : String := "-/"
"""},
     False, None, "string literals containing `/-` and `-/` must not hide `#eval` from comment stripping"),
    ("lean-string-line-comment-hide", "__synthetic_pure_lean__", "decoder_injective",
     {"SyntheticPureLean/DecoderInjective.lean": HONEST_DECODER + """
def s : String := "--" ; #eval IO.println "escaped line comment lint"
"""},
     False, None, "string literal containing `--` must not hide `#eval` on the same line"),
    ("lean-char-quote-comment-hide", "__synthetic_pure_lean__", "decoder_injective",
     {"SyntheticPureLean/DecoderInjective.lean": HONEST_DECODER + """
def q : Char := '"'
def s1 : String := "\\\"/-"
#eval IO.println "escaped via char literal + escaped quote"
def s2 : String := "-/"
"""},
     False, None, "char literal `\"` and escaped quotes must not desync string parsing"),
    ("lean-module-header-hide", "__synthetic_pure_lean__", "decoder_injective",
     {"SyntheticPureLean/DecoderInjective.lean": "module\npublic " + HONEST_DECODER},
     False, None, "Lean 4.36 `module` files split private proofs into `.olean.private` and must be rejected"),
    ("deep-lean-sorryax", "__synthetic_pure_lean__", "decoder_injective",
     {"SyntheticPureLean/DecoderInjective.lean": HONEST_DECODER.replace(
         "  intro a b h\n  have h1 := congrArg c.decode h\n  rw [c.left_inv, c.left_inv] at h1\n  exact h1\n",
         "  exact sorryAx _ false\n")},
     False, None, "sorryAx slips past source lint; only kernel axiom check catches it"),

    # --- Synthetic hill-climb controls (keeps score_const kernel path tested) ---
    ("lean-hillclimb-honest-control", "__synthetic_hillclimb__", "tighten_bound",
     {}, True, 1000.0, "baseline hill-climb proof must verify and score 1000 via the kernel"),
    ("deep-hillclimb-sorryax", "__synthetic_hillclimb__", "tighten_bound",
     {"SyntheticHill/Bound.lean": """import SyntheticHill.Spec
namespace SyntheticHill
def claimedFactor : Nat := 1
theorem bound : ∀ n : Nat, loss n ≤ claimedFactor * n := sorryAx _ false
end SyntheticHill
"""},
     False, None, "unproved hill-climb factor of 1 via sorryAx must be rejected by axiom check"),

    # --- Mathlib v4.36.0 honest control + real upstream mission attack suite ---
    ("mathlib-honest-control", "__synthetic_mathlib__", "sq_sum_expand",
     {}, True, None, "honest Mathlib v4.36.0 proof using `Mathlib.Tactic` + `ring` must pass kernel replay"),
    ("mathlib-arklib-unproved-seed", "arklib-near-capacity-primes", "near_capacity_prime_supply",
     {}, False, None, "unproved ArkLib seed stub with `sorry` must be rejected"),
    ("mathlib-arklib-sorryax", "arklib-near-capacity-primes", "near_capacity_prime_supply",
     {"ArkLibNearCapacity/PrimeSupply.lean": """import ArkLibNearCapacity.Spec
open scoped NNReal
namespace ArkLibNearCapacity
theorem near_capacity_prime_supply (c : ℝ≥0) (hc : 0 < c) : NearCapacityPrimeSupply c :=
  sorryAx _ false
end ArkLibNearCapacity
"""},
     False, None, "ArkLib `sorryAx` bypass must be rejected by the Mathlib kernel axiom check"),
    ("mathlib-pnt-sorryax", "pnt-analytic-foundations", "is_completely_multiplicative_liouville",
     {"PntFoundations/LiouvilleMult.lean": """import PntFoundations.Spec
open ArithmeticFunction
namespace PntFoundations
lemma isCompletelyMultiplicative_liouville :
    IsCompletelyMultiplicative (liouville : ArithmeticFunction ℝ) :=
  sorryAx _ false
end PntFoundations
"""},
     False, None, "PNT+ `sorryAx` bypass must be rejected by the Mathlib kernel axiom check"),
    ("mathlib-pnt-weakened-statement", "pnt-analytic-foundations", "is_completely_multiplicative_liouville",
     {"PntFoundations/LiouvilleMult.lean": """import PntFoundations.Spec
namespace PntFoundations
lemma isCompletelyMultiplicative_liouville : True := trivial
end PntFoundations
"""},
     False, None, "PNT+ weakened theorem statement must be rejected by kernel statement equality"),
    ("mathlib-pnt-import-lean", "pnt-analytic-foundations", "is_completely_multiplicative_liouville",
     {"PntFoundations/LiouvilleMult.lean": """import PntFoundations.Spec
import Lean
namespace PntFoundations
lemma isCompletelyMultiplicative_liouville : True := trivial
end PntFoundations
"""},
     False, None, "Mathlib missions must still block `import Lean`"),
    ("mathlib-pnt-module-cheat", "pnt-analytic-foundations", "is_completely_multiplicative_liouville",
     {"PntFoundations/LiouvilleMult.lean": """module
public import PntFoundations.Spec
open ArithmeticFunction
namespace PntFoundations
public lemma isCompletelyMultiplicative_liouville :
    IsCompletelyMultiplicative (liouville : ArithmeticFunction ℝ) :=
  sorryAx _ false
end PntFoundations
"""},
     False, None, "Mathlib missions must reject Lean 4.36 `module` headers"),

    # --- Repo-Snapshot honest control + tampering attacks (`v4.36.0`) ---
    ("repo-snapshot-honest-control", "__synthetic_repo_snapshot__", "target_add",
     {}, True, None, "honest repo-snapshot proof against frozen sibling module must pass"),
    ("repo-snapshot-sorry", "__synthetic_repo_snapshot__", "target_add",
     {"SnapLib/Target.lean": _SNAP_TARGET_SEED}, False, None,
     "unproved repo-snapshot seed with `sorry` must be rejected"),
    ("repo-snapshot-sorryax", "__synthetic_repo_snapshot__", "target_add",
     {"SnapLib/Target.lean": _SNAP_TARGET_SEED.replace("sorry", "exact sorryAx _ false")},
     False, None, "repo-snapshot `sorryAx` bypass must be rejected by kernel axiom check"),
    ("repo-snapshot-weakened-statement", "__synthetic_repo_snapshot__", "target_add",
     {"SnapLib/Target.lean": """import SnapLib.Core
namespace SnapLib
abbrev targetScale (n : Nat) : Nat := scale n
theorem target_add (a b : Nat) : True := trivial
end SnapLib
"""},
     False, None, "weakened target theorem must be rejected against pinned upstream `.olean`"),
    ("repo-snapshot-weakened-local-abbrev", "__synthetic_repo_snapshot__", "target_add",
     {"SnapLib/Target.lean": """import SnapLib.Core
namespace SnapLib
abbrev targetScale (_n : Nat) : Nat := 0
theorem target_add (a b : Nat) : targetScale (a + b) = targetScale a + targetScale b := rfl
end SnapLib
"""},
     False, None, "mutating a local `abbrev` used in the target theorem type must be rejected by FrozenTypeDeps"),
    ("repo-snapshot-tampered-sibling-module", "__synthetic_repo_snapshot__", "target_add",
     {"SnapLib/Core.lean": """namespace SnapLib
def secretFactor : Nat := 0
def scale (_n : Nat) : Nat := 0
theorem scale_zero : scale 0 = 0 := rfl
end SnapLib
"""},
     False, None, "editing a frozen sibling module must be rejected"),
    ("repo-snapshot-forged-olean", "__synthetic_repo_snapshot__", "target_add",
     {".lake/build/lib/lean/SnapLib/Core.olean": "FORGED_OLEAN_BYTES"},
     False, None, "forged `.olean` dropped into workspace must be rejected"),
    ("repo-snapshot-elab-rules-spoof", "__synthetic_repo_snapshot__", "target_add",
     {"SnapLib/Target.lean": """import SnapLib.Core
import Lean
open Lean Elab Command
namespace SnapLib
abbrev targetScale (n : Nat) : Nat := scale n
theorem target_add (a b : Nat) : targetScale (a + b) = targetScale a + targetScale b := sorryAx _ false
end SnapLib
elab_rules : command
  | `(#print axioms $_) => logInfo "'_sunstead_check' does not depend on any axioms"
"""},
     False, None, "`elab_rules` spoofing + `import Lean` must be rejected in repo-snapshot mode"),
    ("repo-snapshot-module-header", "__synthetic_repo_snapshot__", "target_add",
     {"SnapLib/Target.lean": "module\npublic " + _SNAP_TARGET_HONEST},
     False, None, "Lean 4 `module` / `.olean.private` output must be rejected in repo-snapshot mode"),

    # --- Real full-repo upstream Cryptography mission (`leanprover/LNSym`, Lean v4.35.0) ---
    ("lnsym-unproved-seed", "lnsym-aes-gcm-armv8", "aes_gcm_enc_kernel_run_139",
     {}, False, None, "unmodified upstream LNSym AES-GCM seed with `sorry` must be rejected"),
    ("lnsym-sorryax", "lnsym-aes-gcm-armv8", "aes_gcm_enc_kernel_run_139",
     {"Proofs/AES-GCM/AESGCMEncKernelSym.lean": """import Arm.Memory.Separate
import Proofs.«AES-GCM».AESGCMEncKernelPre
import Tactics.Sym

namespace AESGCMEncKernelProgram

abbrev in_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 0#5) s
abbrev in_bits_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 1#5) s
abbrev Xi_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 3#5) s
abbrev ivec_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 4#5) s
abbrev key_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 5#5) s
abbrev rounds_addr (s : ArmState) : BitVec 64 := (r (StateField.GPR 5#5) s) + 240#64
abbrev Htable_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 6#5) s
abbrev out_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 2#5) s

set_option maxRecDepth 1000000 in
theorem aes_gcm_enc_kernel_program_run_xx (s0 sf : ArmState)
    (h_s0_program : s0.program = aes_gcm_enc_kernel_program)
    (h_s0_err : read_err s0 = .None)
    (h_s0_pc : read_pc s0 = aes_gcm_enc_kernel_program.min)
    (h_s0_sp_aligned : CheckSPAlignment s0)
    (h_run : sf = run 139 s0)
    (h_rounds : 14#32 = read_mem_bytes 4 (rounds_addr s0) s0)
    (h_mem : Memory.Region.pairwiseSeparate
      [⟨(in_addr s0), 128⟩, ⟨(in_bits_addr s0), 64⟩,
       ⟨(Xi_addr s0), 128⟩, ⟨(ivec_addr s0), 128⟩,
       ⟨(key_addr s0), 1984⟩,
       ⟨(Htable_addr s0), 2048⟩,
       ⟨(out_addr s0), 128⟩ ])
    : read_err sf = .None :=
  sorryAx _ false

end AESGCMEncKernelProgram
"""},
     False, None, "LNSym AES-GCM `sorryAx` bypass must be rejected by v4.35.0 kernel axiom check"),
    ("lnsym-weakened-statement", "lnsym-aes-gcm-armv8", "aes_gcm_enc_kernel_run_139",
     {"Proofs/AES-GCM/AESGCMEncKernelSym.lean": """import Arm.Memory.Separate
import Proofs.«AES-GCM».AESGCMEncKernelPre
import Tactics.Sym

namespace AESGCMEncKernelProgram

abbrev in_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 0#5) s
abbrev in_bits_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 1#5) s
abbrev Xi_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 3#5) s
abbrev ivec_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 4#5) s
abbrev key_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 5#5) s
abbrev rounds_addr (s : ArmState) : BitVec 64 := (r (StateField.GPR 5#5) s) + 240#64
abbrev Htable_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 6#5) s
abbrev out_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 2#5) s

theorem aes_gcm_enc_kernel_program_run_xx : True := trivial

end AESGCMEncKernelProgram
"""},
     False, None, "LNSym AES-GCM weakened statement must be rejected against pinned upstream `.olean`"),
    ("lnsym-weakened-local-abbrev", "lnsym-aes-gcm-armv8", "aes_gcm_enc_kernel_run_139",
     {"Proofs/AES-GCM/AESGCMEncKernelSym.lean": """import Arm.Memory.Separate
import Proofs.«AES-GCM».AESGCMEncKernelPre
import Tactics.Sym

namespace AESGCMEncKernelProgram

abbrev in_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 0#5) s
abbrev in_bits_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 1#5) s
abbrev Xi_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 3#5) s
abbrev ivec_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 4#5) s
abbrev key_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 5#5) s
abbrev rounds_addr (_s : ArmState) : BitVec 64 := 0#64
abbrev Htable_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 6#5) s
abbrev out_addr (s : ArmState) : BitVec 64 := r (StateField.GPR 2#5) s

set_option maxRecDepth 1000000 in
theorem aes_gcm_enc_kernel_program_run_xx (s0 sf : ArmState)
    (h_s0_program : s0.program = aes_gcm_enc_kernel_program)
    (h_s0_err : read_err s0 = .None)
    (h_s0_pc : read_pc s0 = aes_gcm_enc_kernel_program.min)
    (h_s0_sp_aligned : CheckSPAlignment s0)
    (h_run : sf = run 139 s0)
    (h_rounds : 14#32 = read_mem_bytes 4 (rounds_addr s0) s0)
    (h_mem : Memory.Region.pairwiseSeparate
      [⟨(in_addr s0), 128⟩, ⟨(in_bits_addr s0), 64⟩,
       ⟨(Xi_addr s0), 128⟩, ⟨(ivec_addr s0), 128⟩,
       ⟨(key_addr s0), 1984⟩,
       ⟨(Htable_addr s0), 2048⟩,
       ⟨(out_addr s0), 128⟩ ])
    : read_err sf = .None :=
  sorryAx _ false

end AESGCMEncKernelProgram
"""},
     False, None, "LNSym mutating local `rounds_addr` abbrev must be rejected by FrozenTypeDeps"),
    ("lnsym-tampered-sibling-module", "lnsym-aes-gcm-armv8", "aes_gcm_enc_kernel_run_139",
     {"Proofs/AES-GCM/AESGCMEncKernelPre.lean": "namespace AESGCMEncKernelProgram\nend AESGCMEncKernelProgram\n"},
     False, None, "LNSym tampered frozen sibling module must be rejected"),
    ("lnsym-elab-rules-spoof", "lnsym-aes-gcm-armv8", "aes_gcm_enc_kernel_run_139",
     {"Proofs/AES-GCM/AESGCMEncKernelSym.lean": """import Arm.Memory.Separate
import Proofs.«AES-GCM».AESGCMEncKernelPre
import Tactics.Sym
import Lean
open Lean Elab Command
namespace AESGCMEncKernelProgram
theorem aes_gcm_enc_kernel_program_run_xx : True := trivial
end AESGCMEncKernelProgram
elab_rules : command
  | `(#print axioms $_) => logInfo "clean"
"""},
     False, None, "LNSym `elab_rules` + `import Lean` spoofing must be rejected"),
    # --- Same-file multi-task `preserve_theorems` guard + LNSym GCM-GMULT mission (Lean v4.35.0) ---
    ("repo-snapshot-preserve-prior-honest", "__synthetic_repo_snapshot__", "target_zero",
     {}, True, None, "multi-task repo-snapshot task 2 with task 1 preserved must pass"),
    ("repo-snapshot-revert-prior-task", "__synthetic_repo_snapshot__", "target_zero",
     {"SnapLib/Target.lean": _SNAP_TARGET_ONLY_T2},
     False, None, "reverting a preserved prior theorem back to `sorry` in a shared file must be rejected"),
    ("lnsym-gcm-unproved-seed-t1", "lnsym-gcm-gmult-armv8", "gcm_polyval_mul_eq_polynomial_mult",
     {}, False, None, "unmodified LNSym GCM-GMULT seed task 1 must be rejected (`sorryAx`)"),
    ("lnsym-gcm-unproved-seed-t2", "lnsym-gcm-gmult-armv8", "polynomial_mult_append",
     {}, False, None, "unmodified LNSym GCM-GMULT seed task 2 must be rejected (`sorryAx`)"),
    ("lnsym-gcm-new-native-decide", "lnsym-gcm-gmult-armv8", "polynomial_mult_append",
     {"Proofs/AES-GCM/GCMGmultV8Sym.lean": """import Specs.GCMV8
import Tests.«AES-GCM».GCMGmultV8Program
namespace GCMGmultV8Program
theorem gcm_polyval_mul_eq_polynomial_mult {x y : BitVec 128} :
  GCMV8.gcm_polyval_mul x y = DPSFP.polynomial_mult x y := by sorry
theorem DPSFP.polynomial_mult_append {p q x y : BitVec 64} :
  DPSFP.polynomial_mult (p ++ q) (x ++ y) =
  ((DPSFP.polynomial_mult p x) ++ 0#128) ^^^
   (0#128 ++ (DPSFP.polynomial_mult q y)) ^^^
   (0#64 ++ (DPSFP.polynomial_mult p y) ++ 0#64) ^^^
   (0#64 ++ (DPSFP.polynomial_mult q x) ++ 0#64) := by native_decide
end GCMGmultV8Program
"""},
     False, None, "introducing a new `native_decide` line in GCMGmultV8Sym must be rejected at lint"),
    ("lnsym-gcm-new-eval", "lnsym-gcm-gmult-armv8", "gcm_polyval_mul_eq_polynomial_mult",
     {"Proofs/AES-GCM/GCMGmultV8Sym.lean": """import Specs.GCMV8
#eval 1 + 1
namespace GCMGmultV8Program
theorem gcm_polyval_mul_eq_polynomial_mult : True := trivial
end GCMGmultV8Program
"""},
     False, None, "introducing a new `#eval` line in GCMGmultV8Sym must be rejected at lint"),
    ("lnsym-gcm-weakened-statement", "lnsym-gcm-gmult-armv8", "gcm_polyval_mul_eq_polynomial_mult",
     {"Proofs/AES-GCM/GCMGmultV8Sym.lean": """import Specs.GCMV8
import Tests.«AES-GCM».GCMGmultV8Program
namespace GCMGmultV8Program
theorem gcm_polyval_mul_eq_polynomial_mult : True := trivial
end GCMGmultV8Program
"""},
     False, None, "weakening `gcm_polyval_mul_eq_polynomial_mult` to `: True` must be rejected by kernel"),

    # --- IEANTN ChebyshevNumerics.v1 (Teorth) ---
    ("ieantn-seed-sorry", "ieantn-chebyshev-kernel", "psi_le_below_11723",
     {},
     False, None, "unmodified IEANTN Chebyshev seed still has sorry and must be rejected"),
    ("ieantn-native-decide", "ieantn-chebyshev-kernel", "psi_le_below_11723",
     {"IEANTN/Nodes/ChebyshevNumerics/v1/Challenge.lean": """import IEANTN.Nodes.ChebyshevNumerics.v1.Conclusions

private theorem native_helper : (1 + 1 == 2) = true := by native_decide

theorem ChebyshevNumerics.v1.challenge_psi_le_below_11723 :
    ChebyshevNumerics.v1.psi_le_below_11723 := by
  have _ := native_helper
  exact sorryAx _ false
"""},
     False, None, "IEANTN Chebyshev proof using `native_decide` (`Lean.ofReduceBool`) must be rejected"),
    ("ieantn-weakened-statement", "ieantn-chebyshev-kernel", "psi_le_below_11723",
     {"IEANTN/Nodes/ChebyshevNumerics/v1/Challenge.lean": """import IEANTN.Nodes.ChebyshevNumerics.v1.Conclusions

theorem ChebyshevNumerics.v1.challenge_psi_le_below_11723 : True := trivial
"""},
     False, None, "IEANTN Chebyshev weakened statement must be rejected"),

    # --- IEANTN Wave 1 missions (short-interval, zeta, pipeline, schoenfeld) ---
    ("ieantn-short-seed-sorry", "ieantn-short-interval-primes", "kadiri_lumley_exp_59",
     {},
     False, None, "unmodified IEANTN short-interval seed still has sorry and must be rejected"),
    ("ieantn-zeta-weakened", "ieantn-zeta-foundations", "patel_cheng_graham_lemma_2",
     {"IEANTN/Nodes/Patel2020/v1/TaskChengGraham2.lean": """import IEANTN.Nodes.Patel2020.v1.Conclusions

theorem Patel2020.v1.challenge_cheng_graham_lemma_2 : True := trivial
"""},
     False, None, "weakened Patel2020 theorem must be rejected by kernel"),
    ("ieantn-pipeline-weakened", "ieantn-chebyshev-pipeline", "bklnw_table8_psi_bound_above",
     {"IEANTN/Nodes/BKLNW/v2/TaskTable8Above.lean": """import IEANTN.Nodes.BKLNW.v2.Conclusions
import IEANTN.Nodes.BKLNWNumerics.v1.Conclusions
import IEANTN.Nodes.Buthe.v1.Conclusions

theorem BKLNW.v2.challenge_table8_psi_bound_above : True := trivial
"""},
     False, None, "weakened BKLNW.v2 theorem must be rejected by kernel"),
    ("ieantn-schoenfeld-seed-sorry", "ieantn-schoenfeld-chebyshev", "psi_upper_theorem_11",
     {},
     False, None, "unmodified IEANTN Schoenfeld seed still has sorry and must be rejected"),

    # --- IEANTN Wave 2 multi-node DAG missions (zero-free regions, zeta logderiv, Buthe) ---
    ("ieantn-zfr-seed-sorry", "ieantn-zero-free-regions", "rosser_schoenfeld_zfr",
     {},
     False, None, "unmodified IEANTN zero-free-regions seed still has sorry and must be rejected"),
    ("ieantn-zfr-weakened", "ieantn-zero-free-regions", "kadiri_2005_zfr",
     {"IEANTN/Nodes/Kadiri2005/v1/TaskZeroFreeRegion.lean": """import IEANTN.Nodes.Kadiri2005.v1.Conclusions
import IEANTN.Nodes.RosserSchoenfeld.v1.Conclusions
import IEANTN.Nodes.Wedeniwski.v1.Conclusions

theorem Kadiri2005.v1.challenge_zero_free_region : True := trivial
"""},
     False, None, "weakened Kadiri2005 theorem must be rejected by kernel"),
    ("ieantn-logderiv-seed-sorry", "ieantn-zeta-logderiv-values", "logderiv_two",
     {},
     False, None, "unmodified IEANTN zeta-logderiv-values seed still has sorry and must be rejected"),
    ("ieantn-logderiv-weakened", "ieantn-zeta-logderiv-values", "no_zeroes_below_first_ordinate",
     {"IEANTN/Nodes/LowZeroes/v1/TaskNoZeroesBelowFirst.lean": """import IEANTN.Nodes.LowZeroes.v1.Conclusions

theorem LowZeroes.v1.challenge_no_zeroes_below_first_ordinate : True := trivial
"""},
     False, None, "weakened LowZeroes theorem must be rejected by kernel"),
    ("ieantn-buthe-seed-sorry", "ieantn-buthe-prime-bounds", "buthe_lemma_3_bounds",
     {},
     False, None, "unmodified IEANTN Buthe seed still has sorry and must be rejected"),
    ("ieantn-buthe-weakened", "ieantn-buthe-prime-bounds", "buthe_theorem_2_li_minus_pi",
     {"IEANTN/Nodes/Buthe/v1/TaskTheorem2LiMinusPi.lean": """import IEANTN.Nodes.Buthe.v1.Conclusions
import IEANTN.Nodes.Buthe.v2.Conclusions
import IEANTN.Nodes.ButheNumerics.v1.Conclusions
import IEANTN.Nodes.FKBJ.v1.Conclusions

theorem Buthe.v1.challenge_theorem_2_li_minus_pi : True := trivial
"""},
     False, None, "weakened Buthe Theorem 2 theorem must be rejected by kernel"),

    # --- AlphaTensor F2 matrix-rank suite (6 shapes) ---
    ("alphatensor-333-baseline", "matrix-rank-alphatensor-f2", "rank_333",
     {},
     True, 23, "honest AlphaTensor <3,3,3> baseline must pass kernel check with score 23"),
    ("alphatensor-445-baseline", "matrix-rank-alphatensor-f2", "rank_445",
     {},
     True, 63, "honest AlphaTensor <4,4,5> baseline must pass kernel check with score 63"),
    ("alphatensor-333-corrupt-table", "matrix-rank-alphatensor-f2", "rank_333",
     {"RankF2/Cert333.lean": "def B334.score333 : Nat := 1\ndef B334.cert333 : List (Nat × Nat × Nat) := [(1, 1, 1)]\n"},
     False, None, "invalid <3,3,3> decomposition must fail decide +kernel"),
    ("alphatensor-333-overwide-mask", "matrix-rank-alphatensor-f2", "rank_333",
     {"RankF2/Cert333.lean": "def B334.score333 : Nat := 1\ndef B334.cert333 : List (Nat × Nat × Nat) := [(1024, 1, 1)]\n"},
     False, None, "bitmask >= 2^9 for <3,3,3> must fail lint"),

    # --- Cross-file repo-snapshot DAG + frozen bridge module controls & attacks (`v4.36.0`) ---
    ("cross-file-dag-t1-honest", "__synthetic_cross_file_dag__", "part1_ok",
     {}, True, None, "cross-file DAG task 1 honest proof (while task 2 seed stays untouched) must pass"),
    ("cross-file-dag-t1-tamper-t2", "__synthetic_cross_file_dag__", "part1_ok",
     {"CrossLib/Part2.lean": _CROSS_PART2_HONEST},
     False, None, "modifying another task's file during task 1 must be rejected"),
    ("cross-file-dag-t2-honest", "__synthetic_cross_file_dag__", "part2_ok",
     {"CrossLib/Part2.lean": _CROSS_PART2_HONEST},
     True, None, "cross-file DAG task 2 honest proof across frozen bridge module must pass"),
    ("cross-file-dag-t2-revert-t1", "__synthetic_cross_file_dag__", "part2_ok",
     {"CrossLib/Part1.lean": _CROSS_PART1_SEED, "CrossLib/Part2.lean": _CROSS_PART2_HONEST},
     False, None, "reverting prerequisite cross-file theorem to `sorry` must be rejected by preserve_theorems"),
    ("cross-file-dag-t2-tamper-bridge", "__synthetic_cross_file_dag__", "part2_ok",
     {"CrossLib/Bridge.lean": "namespace CrossLib\ndef bridgeVal : Nat := 0\nend CrossLib\n",
      "CrossLib/Part2.lean": _CROSS_PART2_HONEST},
     False, None, "dropping a tampered frozen bridge `.lean` file in workspace must be rejected"),

    # --- Real full-repo Cryptography mission (`curve25519-dalek`, Lean v4.31.0 + Mathlib + Aeneas) ---
    ("curve25519-unproved-seed-t1", "curve25519-dalek", "add_assoc_ed25519",
     {}, False, None, "unmodified curve25519-dalek seed task 1 (`add_assoc_Ed25519`) must be rejected"),
    ("curve25519-unproved-seed-t2", "curve25519-dalek", "is_even_iff_in_doubling_image_right",
     {}, False, None, "unmodified curve25519-dalek seed task 2 (`IsEven_iff_in_doubling_image_right`) must be rejected"),
    ("curve25519-t1-weakened-statement", "curve25519-dalek", "add_assoc_ed25519",
     {"Curve25519Dalek/Math/Edwards/Curve.lean": """import Curve25519Dalek.Math.Basic
namespace Edwards
theorem add_assoc_Ed25519 : True := trivial
end Edwards
"""},
     False, None, "weakening `Edwards.add_assoc_Ed25519` to `: True` must be rejected by v4.31.0 kernel"),
    ("curve25519-t1-sorryax", "curve25519-dalek", "add_assoc_ed25519",
     {"Curve25519Dalek/Math/Edwards/Curve.lean": open(
         os.path.join(MISSIONS, "curve25519-dalek", "Curve25519Dalek/Math/Edwards/Curve.lean"),
         encoding="utf-8",
     ).read().replace("  sorry", "  exact sorryAx _ false", 1)},
     False, None, "replacing `add_assoc_Ed25519` sorry with `sorryAx _ false` must be rejected by v4.31.0 axiom check"),
    ("curve25519-t1-weakened-local-def", "curve25519-dalek", "add_assoc_ed25519",
     {"Curve25519Dalek/Math/Edwards/Curve.lean": """import Curve25519Dalek.Math.Basic
namespace Edwards
structure EdwardsCurve (F : Type) where
  a : F
  d : F
def Ed25519 : EdwardsCurve CurveField := { a := -1, d := 0 }
structure Point {F : Type} [Mul F] [Add F] [Pow F ℕ] [One F] (C : EdwardsCurve F) where
  x : F
  y : F
  on_curve : C.a * x^2 + y^2 = 1 + C.d * x^2 * y^2
instance : Add (Point Ed25519) := ⟨fun p _ => p⟩
theorem add_assoc_Ed25519 (p q r : Point Ed25519) : p + q + r = p + (q + r) := rfl
end Edwards
"""},
     False, None, "mutating local `Ed25519`/`Add` definitions to make `add_assoc_Ed25519` hold by `rfl` must be rejected by FrozenTypeDeps"),
    ("curve25519-t1-elab-rules-spoof", "curve25519-dalek", "add_assoc_ed25519",
     {"Curve25519Dalek/Math/Edwards/Curve.lean": """import Curve25519Dalek.Math.Basic
import Lean
open Lean Elab Command
namespace Edwards
theorem add_assoc_Ed25519 : True := trivial
end Edwards
elab_rules : command
  | `(#print axioms $_) => logInfo "clean"
"""},
     False, None, "curve25519 `elab_rules` + `import Lean` spoofing must be rejected"),
    ("curve25519-t1-tampered-sibling", "curve25519-dalek", "add_assoc_ed25519",
     {"Curve25519Dalek/Math/Basic.lean": "namespace Curve25519Dalek.Math\nend Curve25519Dalek.Math\n"},
     False, None, "curve25519 tampered frozen sibling module must be rejected"),
    ("curve25519-t1-tampered-t2-file", "curve25519-dalek", "add_assoc_ed25519",
     {"Curve25519Dalek/Math/Ristretto/Representation.lean": "-- tampered during task 1\n"},
     False, None, "modifying Ristretto/Representation.lean during task 1 must be rejected"),
    ("curve25519-t2-weakened-iseven", "curve25519-dalek", "is_even_iff_in_doubling_image_right",
     {"Curve25519Dalek/Math/Ristretto/Representation.lean": """import Curve25519Dalek.Math.Basic
import Curve25519Dalek.Math.Edwards.Curve
import Curve25519Dalek.Math.Edwards.Representation
namespace curve25519_dalek.ristretto
open Edwards
def IsEven (_P : Point Ed25519) : Prop := False
theorem IsEven_iff_in_doubling_image_right (P : Point Ed25519) :
    IsEven P → ∃ Q : Point Ed25519, P = Q + Q :=
  fun h => False.elim h
end curve25519_dalek.ristretto
"""},
     False, None, "weakening local `IsEven` definition to `False` so `IsEven_iff_in_doubling_image_right` holds vacuously must be rejected by FrozenTypeDeps"),

    # --- Opt-in Lean 4.36 `module`-system (`.olean.private`) repo-snapshot controls & attacks ---
    ("module-snapshot-honest-control", "__synthetic_module_snapshot__", "mod_add",
     {}, True, None, "honest opt-in Lean 4.36 `module` proof using a private helper must pass kernel replay"),
    ("module-snapshot-private-sorryax", "__synthetic_module_snapshot__", "mod_add",
     {"ModSnap/Target.lean": """module
public import ModSnap.Core

namespace ModSnap
@[expose] public def localScale (n : Nat) : Nat := scaled n

private theorem hidden_cheat (a b : Nat) : localScale (a + b) = localScale a + localScale b :=
  sorryAx _ false

public theorem mod_add (a b : Nat) : localScale (a + b) = localScale a + localScale b :=
  hidden_cheat a b
end ModSnap
"""},
     False, None, "hidden `sorryAx` inside a `private theorem` in `.olean.private` must be caught by kernel replay"),
    ("module-snapshot-private-axiom", "__synthetic_module_snapshot__", "mod_add",
     {"ModSnap/Target.lean": """module
public import ModSnap.Core

namespace ModSnap
@[expose] public def localScale (n : Nat) : Nat := scaled n

private axiom hidden_ax (a b : Nat) : localScale (a + b) = localScale a + localScale b

public theorem mod_add (a b : Nat) : localScale (a + b) = localScale a + localScale b :=
  hidden_ax a b
end ModSnap
"""},
     False, None, "`private axiom` in a `module` file must be rejected"),
    ("module-snapshot-private-import-lean", "__synthetic_module_snapshot__", "mod_add",
     {"ModSnap/Target.lean": """module
public import ModSnap.Core
private import Lean

namespace ModSnap
@[expose] public def localScale (n : Nat) : Nat := scaled n
public theorem mod_add (a b : Nat) : localScale (a + b) = localScale a + localScale b := by
  unfold localScale scaled baseFactor
  omega
end ModSnap
"""},
     False, None, "`private import Lean` in a `module` file must still be blocked by allowed_import_prefixes lint"),
    ("module-snapshot-weakened-local-def", "__synthetic_module_snapshot__", "mod_add",
     {"ModSnap/Target.lean": """module
public import ModSnap.Core

namespace ModSnap
@[expose] public def localScale (_n : Nat) : Nat := 0
public theorem mod_add (a b : Nat) : localScale (a + b) = localScale a + localScale b := rfl
end ModSnap
"""},
     False, None, "mutating frozen local `localScale` in a `module` file must be rejected by FrozenTypeDeps"),
    ("module-snapshot-forged-private-olean", "__synthetic_module_snapshot__", "mod_add",
     {".lake/build/lib/lean/ModSnap/Core.olean.private": "FORGED_PRIVATE_OLEAN"},
     False, None, "forged `.olean.private` dropped into workspace must be rejected at lint"),
]


def make_work_tree(mission, files):
    d = tempfile.mkdtemp(prefix="sunstead-redteam-")
    work = os.path.join(d, "work")
    if mission in SYNTHETIC_TREES:
        os.makedirs(work, exist_ok=True)
        for rel, content in SYNTHETIC_TREES[mission].items():
            dst = os.path.join(work, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8") as f:
                f.write(content)
    else:
        shutil.copytree(os.path.join(MISSIONS, mission), work,
                        ignore=shutil.ignore_patterns(".git", ".lake"))
    for rel, content in files.items():
        dst = os.path.join(work, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="utf-8") as f:
            f.write(content)
    os.chmod(d, 0o755)
    for dirpath, dirnames, filenames in os.walk(work):
        os.chmod(dirpath, 0o755)
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            os.chmod(p, 0o755 if fn == "verify" else 0o644)
    return d, work


def parse_verdict(stdout):
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                return json.loads(line)
            except ValueError:
                pass
    return None


def run_docker(mission, task, work, timeout):
    image = IMAGES[mission]
    create = ["docker", "create", "--network=none", "--cpus=2", "--memory=6144m",
              "--pids-limit=512", "--user=0:0", "--cap-drop=ALL",
              "--cap-add=SETUID", "--cap-add=SETGID",
              "--security-opt=no-new-privileges", "-w", "/work", image, "./verify", task]
    cid = subprocess.run(create, capture_output=True, text=True, check=True).stdout.strip()
    try:
        subprocess.run(["docker", "cp", f"{work}/.", f"{cid}:/work"], check=True,
                       capture_output=True)
        p = subprocess.run(["docker", "start", "-a", cid], capture_output=True, text=True,
                           timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    finally:
        subprocess.run(["docker", "rm", "-f", cid], capture_output=True)


def run_local(mission, task, work, timeout):
    p = subprocess.run(["./verify", task], cwd=work, capture_output=True, text=True,
                       timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--local", action="store_true")
    ap.add_argument("--mission", action="append")
    ap.add_argument("--exclude-mission", action="append")
    ap.add_argument("--case", action="append")
    ap.add_argument("--timeout", type=int, default=300)
    args = ap.parse_args()

    failures = 0
    for name, mission, task, files, expect_ok, expect_score, why in CASES:
        if args.mission and mission not in args.mission:
            continue
        if args.exclude_mission and mission in args.exclude_mission:
            continue
        if args.case and name not in args.case:
            continue
        tmp, work = make_work_tree(mission, files)
        try:
            runner = run_local if args.local else run_docker
            rc, out, err = runner(mission, task, work, args.timeout)
        except subprocess.TimeoutExpired:
            rc, out, err = -1, "", "timeout"
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        verdict = parse_verdict(out) or {}
        ok = bool(verdict.get("ok")) and rc == 0
        good = ok == expect_ok and (expect_score is None or verdict.get("score") == expect_score)
        failures += 0 if good else 1
        status = "PASS" if good else "FAIL"
        want = "accept" if expect_ok else "reject"
        print(f"[{status}] {name}: expected {want}, got {'accept' if ok else 'reject'}"
              f" - {verdict.get('summary', (err or out).strip()[-200:])}")
        if not good:
            print(f"         why this case exists: {why}")
    print(f"\n{failures} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
