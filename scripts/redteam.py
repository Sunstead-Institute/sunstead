#!/usr/bin/env python3
"""
Sunstead Lean 4 red-team suite: submissions that MUST be rejected, plus honest
controls that MUST be accepted, run directly against the verifier image
(the same way the hub runs it) so the checks don't depend on the hub.

    ./scripts/build-verifiers.sh && python3 scripts/redteam.py            # Docker (default)
    python3 scripts/redteam.py --mission tier1-metacomplexity-dag         # one mission
    sudo -E python3 scripts/redteam.py --local                            # no Docker: run ./verify
                                                                          # directly (needs root,
                                                                          # the sunstead-* users and
                                                                          # /opt/sunstead installed)

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
IMAGES = {
    "tier1-metacomplexity-dag": "sunstead/verifier-lean4:v0.1",
    "tier1-crypto-algebra-dag": "sunstead/verifier-lean4:v0.1",
    "tier2-soundness-bound": "sunstead/verifier-lean4:v0.1",
    "tier2-coding-bounds": "sunstead/verifier-lean4:v0.1",
}

HONEST_DECODER = """import MetaComplexity.Spec

namespace MetaComplexity

theorem encode_injective_of_lossless {n k : Nat} (c : LosslessCompressor n k) :
    Injective c.encode := by
  intro a b h
  have h1 := congrArg c.decode h
  rw [c.left_inv, c.left_inv] at h1
  exact h1

end MetaComplexity
"""

# Each case: (name, mission, task, {path: content}, expect_ok, expect_score_or_None, why)
CASES = [
    ("lean-honest-control", "tier1-metacomplexity-dag", "decoder_injective",
     {"MetaComplexity/DecoderInjective.lean": HONEST_DECODER}, True, None,
     "honest proof must still pass"),
    ("lean-sorry", "tier1-metacomplexity-dag", "decoder_injective",
     {"MetaComplexity/DecoderInjective.lean": HONEST_DECODER.replace(
         "  intro a b h\n  have h1 := congrArg c.decode h\n  rw [c.left_inv, c.left_inv] at h1\n  exact h1\n",
         "  sorry\n")},
     False, None, "plain sorry"),
    ("lean-spoof-axiom-report", "tier1-metacomplexity-dag", "pigeonhole_fin",
     {"MetaComplexity/Pigeonhole.lean": """import MetaComplexity.Spec
import Lean
open Lean Elab Command

namespace MetaComplexity
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  sorry
end MetaComplexity

elab_rules : command
  | `(#print axioms $_) => logInfo "'sunstead_audit' does not depend on any axioms"
"""},
     False, None, "an imported elaborator rewrote #print axioms output; the old audit trusted that text"),
    ("lean-eval-spoof", "tier1-metacomplexity-dag", "pigeonhole_fin",
     {"MetaComplexity/Pigeonhole.lean": """import MetaComplexity.Spec
namespace MetaComplexity
axiom cheat : ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := cheat
end MetaComplexity
#eval IO.println "'sunstead_audit' does not depend on any axioms"
"""},
     False, None, "custom axiom plus printed fake axiom report"),
    ("lean-weakened-statement", "tier1-metacomplexity-dag", "pigeonhole_fin",
     {"MetaComplexity/Pigeonhole.lean": """import MetaComplexity.Spec
namespace MetaComplexity
theorem no_inj_lt : ∀ {n m : Nat}, m < n → True := fun _ => trivial
end MetaComplexity
"""},
     False, None, "target theorem states something weaker than the frozen statement"),
    ("lean-notation-hijack", "tier1-metacomplexity-dag", "pigeonhole_fin",
     {"MetaComplexity/Pigeonhole.lean": """import MetaComplexity.Spec
namespace MetaComplexity
macro_rules | `(¬ $p) => `(True)
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  intros; trivial
end MetaComplexity
"""},
     False, None, "redefining `¬` so an elaborated audit statement means something else"),
    ("lean-build-time-tamper", "tier1-metacomplexity-dag", "pigeonhole_fin",
     {"MetaComplexity/Pigeonhole.lean": """import MetaComplexity.Spec
namespace MetaComplexity
theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  sorry
end MetaComplexity
#eval (do
  let _ ← IO.Process.spawn { cmd := "sh", args := #["-c",
    "while true; do for f in /tmp/*/_SunsteadAudit.lean /tmp/verify_run/_SunsteadAudit.lean; do " ++
    "[ -f \\"$f\\" ] && printf '#eval IO.println \\"ok\\"\\\\n' > \\"$f\\"; done; sleep 0.05; done"] }
  pure () : IO Unit)
"""},
     False, None, "build-time #eval starts a process that rewrites the audit file"),
    ("lean-string-block-comment-hide", "tier1-metacomplexity-dag", "decoder_injective",
     {"MetaComplexity/DecoderInjective.lean": HONEST_DECODER + """
def s1 : String := "/-"
#eval IO.println "escaped block comment lint"
def s2 : String := "-/"
"""},
     False, None, "string literals containing `/-` and `-/` must not hide `#eval` from comment stripping"),
    ("lean-string-line-comment-hide", "tier1-metacomplexity-dag", "decoder_injective",
     {"MetaComplexity/DecoderInjective.lean": HONEST_DECODER + """
def s : String := "--" ; #eval IO.println "escaped line comment lint"
"""},
     False, None, "string literal containing `--` must not hide `#eval` on the same line"),
    ("lean-char-quote-comment-hide", "tier1-metacomplexity-dag", "decoder_injective",
     {"MetaComplexity/DecoderInjective.lean": HONEST_DECODER + """
def q : Char := '"'
def s1 : String := "\\\"/-"
#eval IO.println "escaped via char literal + escaped quote"
def s2 : String := "-/"
"""},
     False, None, "char literal `\"` and escaped quotes must not desync string parsing"),
    ("lean-hillclimb-honest-control", "tier2-soundness-bound", "tighten_multi_user_bound",
     {}, True, 1000.0, "the seed's baseline proof must verify and score 1000 via the kernel"),
    # These slip past the source hygiene scan on purpose, so the kernel
    # replay + axiom check is what must reject them.
    ("deep-lean-sorryax", "tier1-metacomplexity-dag", "decoder_injective",
     {"MetaComplexity/DecoderInjective.lean": HONEST_DECODER.replace(
         "  intro a b h\n  have h1 := congrArg c.decode h\n  rw [c.left_inv, c.left_inv] at h1\n  exact h1\n",
         "  exact sorryAx _ false\n")},
     False, None, "sorryAx is not the word `sorry`, so only the axiom check can catch it"),
    ("deep-hillclimb-sorryax", "tier2-soundness-bound", "tighten_multi_user_bound",
     {"SoundnessBound/MultiUserBound.lean": """import SoundnessBound.Spec
namespace SoundnessBound
def claimedMultiUserFactor : Nat := 1
theorem multi_user_bound :
    ∀ u q : Nat, u ≥ 1 → q ≥ 1 →
      100 * multiUserLoss u q ≤ claimedMultiUserFactor * ((u + q) * (u + q)) :=
  sorryAx _ false
end SoundnessBound
"""},
     False, None, "unproved factor of 1 without any #eval: the axiom check must reject it"),
    ("lean-hillclimb-score-spoof", "tier2-soundness-bound", "tighten_multi_user_bound",
     {"SoundnessBound/MultiUserBound.lean": """import SoundnessBound.Spec
namespace SoundnessBound
def claimedMultiUserFactor : Nat := 1
theorem multi_user_bound :
    ∀ u q : Nat, u ≥ 1 → q ≥ 1 →
      100 * multiUserLoss u q ≤ claimedMultiUserFactor * ((u + q) * (u + q)) := by
  sorry
end SoundnessBound
#eval IO.println "SUNSTEAD_SCORE=1"
#eval IO.println "'sunstead_audit_bound' does not depend on any axioms"
"""},
     False, None, "fake score line and fake axiom report for an unproved factor of 1"),
]


def make_work_tree(mission, files):
    d = tempfile.mkdtemp(prefix="sunstead-redteam-")
    work = os.path.join(d, "work")
    shutil.copytree(os.path.join(MISSIONS, mission), work,
                    ignore=shutil.ignore_patterns(".git", ".lake"))
    for rel, content in files.items():
        with open(os.path.join(work, rel), "w", encoding="utf-8") as f:
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
    create = ["docker", "create", "--network=none", "--cpus=2", "--memory=4096m",
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
