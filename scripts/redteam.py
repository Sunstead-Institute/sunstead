#!/usr/bin/env python3
"""
Sunstead Lean 4.36.0 + Mathlib red-team suite: submissions that MUST be rejected,
plus honest controls (pure Lean, Mathlib `ring`/`norm_num`, and kernel hill-climb)
that MUST be accepted, run directly against `sunstead/verifier-lean4:v0.2`
(the same way the hub runs it) so the checks don't depend on the hub.

    ./scripts/build-verifiers.sh && python3 scripts/redteam.py            # Docker (default)
    python3 scripts/redteam.py --mission onboarding-sandbox               # one mission
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
IMAGES = {
    "onboarding-sandbox": DEFAULT_IMAGE,
    "arklib-near-capacity-primes": DEFAULT_IMAGE,
    "pnt-analytic-foundations": DEFAULT_IMAGE,
    "__synthetic_mathlib__": DEFAULT_IMAGE,
    "__synthetic_hillclimb__": DEFAULT_IMAGE,
}

HONEST_DECODER = """import OnboardingSandbox.Spec

namespace OnboardingSandbox

theorem encode_injective_of_lossless {n k : Nat} (c : LosslessCompressor n k) :
    Injective c.encode := by
  intro a b h
  have h1 := congrArg c.decode h
  rw [c.left_inv, c.left_inv] at h1
  exact h1

end OnboardingSandbox
"""

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

SYNTHETIC_TREES = {
    "__synthetic_mathlib__": SYNTHETIC_MATHLIB_TREE,
    "__synthetic_hillclimb__": SYNTHETIC_HILLCLIMB_TREE,
}

# Each case: (name, mission, task, {path: content}, expect_ok, expect_score_or_None, why)
CASES = [
    # --- Pure Lean 4.36.0 attacks + honest control (`onboarding-sandbox`) ---
    ("lean-honest-control", "onboarding-sandbox", "decoder_injective",
     {"OnboardingSandbox/DecoderInjective.lean": HONEST_DECODER}, True, None,
     "honest pure-Lean proof must pass"),
    ("lean-sorry", "onboarding-sandbox", "decoder_injective",
     {"OnboardingSandbox/DecoderInjective.lean": HONEST_DECODER.replace(
         "  intro a b h\n  have h1 := congrArg c.decode h\n  rw [c.left_inv, c.left_inv] at h1\n  exact h1\n",
         "  sorry\n")},
     False, None, "plain sorry"),
    ("lean-spoof-axiom-report", "onboarding-sandbox", "pigeonhole_fin",
     {"OnboardingSandbox/Pigeonhole.lean": """import OnboardingSandbox.Spec
import Lean
open Lean Elab Command

namespace OnboardingSandbox
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  sorry
end OnboardingSandbox

elab_rules : command
  | `(#print axioms $_) => logInfo "'sunstead_audit' does not depend on any axioms"
"""},
     False, None, "an imported elaborator rewrote #print axioms output"),
    ("lean-eval-spoof", "onboarding-sandbox", "pigeonhole_fin",
     {"OnboardingSandbox/Pigeonhole.lean": """import OnboardingSandbox.Spec
namespace OnboardingSandbox
axiom cheat : ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := cheat
end OnboardingSandbox
#eval IO.println "'sunstead_audit' does not depend on any axioms"
"""},
     False, None, "custom axiom plus printed fake axiom report"),
    ("lean-weakened-statement", "onboarding-sandbox", "pigeonhole_fin",
     {"OnboardingSandbox/Pigeonhole.lean": """import OnboardingSandbox.Spec
namespace OnboardingSandbox
theorem no_inj_lt : ∀ {n m : Nat}, m < n → True := fun _ => trivial
end OnboardingSandbox
"""},
     False, None, "target theorem states something weaker than the frozen statement"),
    ("lean-notation-hijack", "onboarding-sandbox", "pigeonhole_fin",
     {"OnboardingSandbox/Pigeonhole.lean": """import OnboardingSandbox.Spec
namespace OnboardingSandbox
macro_rules | `(¬ $p) => `(True)
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  intros; trivial
end OnboardingSandbox
"""},
     False, None, "redefining `¬` so an elaborated audit statement means something else"),
    ("lean-build-time-tamper", "onboarding-sandbox", "pigeonhole_fin",
     {"OnboardingSandbox/Pigeonhole.lean": """import OnboardingSandbox.Spec
namespace OnboardingSandbox
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  sorry
end OnboardingSandbox
#eval (do
  let _ ← IO.Process.spawn { cmd := "sh", args := #["-c",
    "while true; do for f in /tmp/*/_SunsteadAudit.lean /tmp/verify_run/_SunsteadAudit.lean; do " ++
    "[ -f \\"$f\\" ] && printf '#eval IO.println \\"ok\\"\\\\n' > \\"$f\\"; done; sleep 0.05; done"] }
  pure () : IO Unit)
"""},
     False, None, "build-time #eval starts a process that rewrites the audit file"),
    ("lean-string-block-comment-hide", "onboarding-sandbox", "decoder_injective",
     {"OnboardingSandbox/DecoderInjective.lean": HONEST_DECODER + """
def s1 : String := "/-"
#eval IO.println "escaped block comment lint"
def s2 : String := "-/"
"""},
     False, None, "string literals containing `/-` and `-/` must not hide `#eval` from comment stripping"),
    ("lean-string-line-comment-hide", "onboarding-sandbox", "decoder_injective",
     {"OnboardingSandbox/DecoderInjective.lean": HONEST_DECODER + """
def s : String := "--" ; #eval IO.println "escaped line comment lint"
"""},
     False, None, "string literal containing `--` must not hide `#eval` on the same line"),
    ("lean-char-quote-comment-hide", "onboarding-sandbox", "decoder_injective",
     {"OnboardingSandbox/DecoderInjective.lean": HONEST_DECODER + """
def q : Char := '"'
def s1 : String := "\\\"/-"
#eval IO.println "escaped via char literal + escaped quote"
def s2 : String := "-/"
"""},
     False, None, "char literal `\"` and escaped quotes must not desync string parsing"),
    ("lean-module-header-hide", "onboarding-sandbox", "decoder_injective",
     {"OnboardingSandbox/DecoderInjective.lean": "module\npublic " + HONEST_DECODER},
     False, None, "Lean 4.36 `module` files split private proofs into `.olean.private` and must be rejected"),
    ("deep-lean-sorryax", "onboarding-sandbox", "decoder_injective",
     {"OnboardingSandbox/DecoderInjective.lean": HONEST_DECODER.replace(
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
    ap.add_argument("--case", action="append")
    ap.add_argument("--timeout", type=int, default=300)
    args = ap.parse_args()

    failures = 0
    for name, mission, task, files, expect_ok, expect_score, why in CASES:
        if args.mission and mission not in args.mission:
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
