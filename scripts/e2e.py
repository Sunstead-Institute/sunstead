#!/usr/bin/env python3
"""
End-to-end test of the Sunstead hub (Cloudflare Worker + Durable Object +
verifier containers), using only the public HTTP protocol from /join.txt.

    cd cloudflare && npm run dev          # local dev server (needs Docker)
    SUNSTEAD_URL=http://localhost:5173 python3 scripts/e2e.py

Never point this at production: it registers contributors and submits patches.
"""
import io
import json
import os
import random
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request

BASE = os.environ.get("SUNSTEAD_URL", "http://localhost:5173").rstrip("/")
if "sunstead.org" in BASE and os.environ.get("SUNSTEAD_E2E_ALLOW_PROD") != "1":
    sys.exit("refusing to run e2e against production (set SUNSTEAD_E2E_ALLOW_PROD=1 to override)")

RUN = f"{random.randrange(16**6):06x}"


def req(method, path, body=None, key=None, raw=False):
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"User-Agent": "sunstead-e2e/0.2"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if key:
        headers["Authorization"] = f"Bearer {key}"
    r = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=600) as resp:
            payload = resp.read()
            if raw:
                return resp.status, payload
            ctype = resp.headers.get("Content-Type", "")
            return resp.status, (json.loads(payload) if "json" in ctype else payload.decode())
    except urllib.error.HTTPError as e:
        payload = e.read()
        try:
            return e.code, json.loads(payload)
        except Exception:
            return e.code, payload.decode("utf-8", errors="replace")


def register(handle):
    code, res = req("POST", "/api/contributors/register",
                    {"handle": f"{handle}-{RUN}", "display_name": handle})
    assert code in (200, 201) and res.get("api_key", "").startswith("ss_live_"), (code, res)
    return res["api_key"]


def make_patch(mission_id, edits):
    code, data = req("GET", f"/api/missions/{mission_id}/bundle.tar.gz", raw=True)
    assert code == 200, f"bundle download failed: {code}"
    with tempfile.TemporaryDirectory() as tmp:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
            tf.extractall(tmp, filter="data")
        for rel, content in edits.items():
            with open(os.path.join(tmp, rel), "w", encoding="utf-8") as f:
                f.write(content)
        return subprocess.check_output(["git", "diff"], cwd=tmp, text=True)


def submit(mission, task, key, edits):
    patch = make_patch(mission, edits)
    return req("POST", f"/api/missions/{mission}/tasks/{task}/submit", {"patch": patch}, key=key)


def ok(msg):
    print(f"  [PASS] {msg}")


CENTERED_MOD = """use crate::spec::{HALF_Q, Q};
pub fn centered_mod(a: i32) -> i32 {
    let diff = a - (HALF_Q + 1);
    let mask = !(diff >> 31);
    a - (Q & mask)
}
"""
MU_300 = """import SoundnessBound.Spec

namespace SoundnessBound

def claimedMultiUserFactor : Nat := 300

theorem multi_user_bound :
    ∀ u q : Nat, u ≥ 1 → q ≥ 1 →
      100 * multiUserLoss u q ≤ claimedMultiUserFactor * ((u + q) * (u + q)) := by
  intro u q hu hq
  unfold multiUserLoss claimedMultiUserFactor
  have hdiv2 : 2 * ((q * (q - 1)) / 2) ≤ q * (q - 1) := Nat.mul_div_le _ 2
  have hsub : q * (q - 1) ≤ q * q := Nat.mul_le_mul_left q (Nat.sub_le q 1)
  have hdiv4 : 4 * ((q * q) / 4) ≤ q * q := Nat.mul_div_le _ 4
  have hexp : (u + q) * (u + q) = u * u + 2 * (u * q) + q * q := by
    rw [Nat.add_mul, Nat.mul_add, Nat.mul_add, Nat.mul_comm q u]
    omega
  have hu2 : u ≤ u * u := by
    calc u = u * 1 := (Nat.mul_one u).symm
      _ ≤ u * u := Nat.mul_le_mul_left u hu
  have hq2 : q ≤ q * q := by
    calc q = q * 1 := (Nat.mul_one q).symm
      _ ≤ q * q := Nat.mul_le_mul_left q hq
  omega

end SoundnessBound
"""
DECODER = """import MetaComplexity.Spec

namespace MetaComplexity

theorem encode_injective_of_lossless {n k : Nat} (c : LosslessCompressor n k) :
    Injective c.encode := by
  intro a b h
  have h1 := congrArg c.decode h
  rw [c.left_inv, c.left_inv] at h1
  exact h1

end MetaComplexity
"""
PIGEONHOLE = """import MetaComplexity.Spec

namespace MetaComplexity

theorem no_inj_lt :
    ∀ {n m : Nat}, m < n → ∀ (f : Fin n → Fin m), ¬ Injective f := by
  intro n m
  induction m generalizing n with
  | zero =>
    intro hlt f _
    exact Fin.elim0 (f ⟨0, hlt⟩)
  | succ m ih =>
    intro hlt f hinj
    cases n with
    | zero => omega
    | succ n =>
      let y : Fin (m + 1) := f ⟨n, Nat.lt_succ_self n⟩
      have hne : ∀ (i : Fin n), (f ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩).val ≠ y.val := by
        intro i heq
        have hfin : f ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩ = y := Fin.ext heq
        have hi := hinj ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩ ⟨n, Nat.lt_succ_self n⟩ hfin
        have hval : i.val = n := congrArg Fin.val hi
        omega
      let g : Fin n → Fin m := fun i =>
        let v := f ⟨i.val, Nat.lt_succ_of_lt i.isLt⟩
        if hltv : v.val < y.val then
          ⟨v.val, by omega⟩
        else
          ⟨v.val - 1, by
            have := hne i
            omega⟩
      have hginj : Injective g := by
        intro a b hab
        have hval : (g a).val = (g b).val := congrArg Fin.val hab
        dsimp only [g] at hval
        have hna := hne a
        have hnb := hne b
        have hfeq : f ⟨a.val, Nat.lt_succ_of_lt a.isLt⟩ = f ⟨b.val, Nat.lt_succ_of_lt b.isLt⟩ := by
          apply Fin.ext
          split at hval <;> split at hval <;> dsimp only at hval <;> omega
        have hab' := hinj _ _ hfeq
        have hval_ab : a.val = b.val := by injection hab'
        exact Fin.ext hval_ab
      exact ih (by omega) g hginj

end MetaComplexity
"""


def main():
    print(f"==> Testing Sunstead hub at {BASE} (run {RUN})")

    code, health = req("GET", "/api/health")
    assert code == 200 and health.get("ok") is True, health
    ok("/api/health")

    code, missions = req("GET", "/api/missions")
    assert code == 200
    ids = {m["id"] for m in missions["missions"]}
    assert {"tier3-mldsa-arith", "tier2-soundness-bound", "tier1-metacomplexity-dag"} <= ids, ids
    ok(f"/api/missions lists {len(ids)} missions")

    code, join_txt = req("GET", "/join.txt")
    assert code == 200 and "contributors/register" in join_txt
    ok("/join.txt")

    # Identity is required for claims and submissions.
    code, res = req("POST", "/api/missions/tier3-mldsa-arith/tasks/centered_mod/claim", {})
    assert code == 401, (code, res)
    ok("anonymous claim rejected (401)")

    alice = register("alice-rust")
    bob = register("bob-lean")
    mallory = register("mallory")
    ok("registered 3 contributors")

    # Policy gate: frozen spec edits are rejected before any container runs.
    code, res = submit("tier3-mldsa-arith", "centered_mod", mallory,
                       {"src/spec.rs": "pub const Q: i32 = 1;\n"})
    assert code == 422 and "frozen" in json.dumps(res), (code, res)
    ok("frozen-path tampering rejected (422)")

    # Hygiene: delegating to the reference implementation is rejected by the verifier.
    code, res = submit("tier3-mldsa-arith", "centered_mod", mallory,
                       {"src/centered_mod.rs": "use crate::spec::spec_centered_mod;\n"
                                               "pub fn centered_mod(a: i32) -> i32 { spec_centered_mod(a) }\n"})
    assert code == 422 and "spec.rs" in json.dumps(res), (code, res)
    ok("spec delegation rejected by the verifier")

    # Claim, then an honest Tier 3 solution.
    code, res = req("POST", "/api/missions/tier3-mldsa-arith/tasks/centered_mod/claim", {}, key=alice)
    assert code == 200 and res.get("claimed") is True, (code, res)
    code, res = req("POST", "/api/missions/tier3-mldsa-arith/tasks/centered_mod/claim", {}, key=bob)
    assert code in (409, 422), (code, res)
    ok("lease claimed; second claimant blocked")
    code, res = submit("tier3-mldsa-arith", "centered_mod", alice, {"src/centered_mod.rs": CENTERED_MOD})
    assert code == 200 and res.get("accepted") is True, (code, res)
    ok(f"Tier 3 centered_mod accepted ({res.get('verify_ms')} ms)")

    # Tier 1: honest proof accepted; sorryAx proof rejected by the kernel axiom check.
    code, res = submit("tier1-metacomplexity-dag", "pigeonhole_fin", mallory,
                       {"MetaComplexity/Pigeonhole.lean": PIGEONHOLE.replace(
                           PIGEONHOLE[PIGEONHOLE.index(":= by"):PIGEONHOLE.index("end MetaComplexity")],
                           ":=\n  sorryAx _ false\n\n")})
    assert code == 422 and "sorryAx" in json.dumps(res), (code, res)
    ok("sorryAx proof rejected by the kernel axiom check")
    code, res = submit("tier1-metacomplexity-dag", "decoder_injective", bob,
                       {"MetaComplexity/DecoderInjective.lean": DECODER})
    assert code == 200 and res.get("accepted") is True, (code, res)
    ok(f"Tier 1 decoder_injective accepted ({res.get('verify_ms')} ms)")

    # Tier 2 hill-climb: 1000 -> 300 accepted with log-ratio points; regression rejected.
    code, res = submit("tier2-soundness-bound", "tighten_multi_user_bound", bob,
                       {"SoundnessBound/MultiUserBound.lean": MU_300})
    assert code == 200 and res.get("accepted") is True and res.get("score") == 300.0, (code, res)
    assert res.get("points_awarded") == 300, res  # floor(250 * ln(1000/300)) = 300
    ok("Tier 2 1000 -> 300 accepted, 300 points")
    code, res = submit("tier2-soundness-bound", "tighten_multi_user_bound", alice,
                       {"SoundnessBound/MultiUserBound.lean": MU_300.replace(":= 300", ":= 500")})
    assert code == 422 and "strictly improve" in json.dumps(res), (code, res)
    ok("Tier 2 regression rejected")

    code, board = req("GET", "/api/leaderboard")
    assert code == 200
    ok("leaderboard reachable")

    # Tier 3 Verus: a proof over the verbatim upstream base16ct code.
    fixture = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "redteam-fixtures", "base16ct", "decode_pair.rs")
    with open(fixture, encoding="utf-8") as f:
        code, res = submit("tier3-base16ct-verus", "decode_pair_flags", alice,
                           {"src/decode_pair.rs": f.read()})
    assert code == 200 and res.get("accepted") is True, (code, res)
    ok(f"Verus decode_pair_flags accepted ({res.get('verify_ms')} ms)")

    # Phase 4: accepted work is published as git history that rebuilds the live state.
    mission = "tier3-mldsa-arith"
    code, hist = req("GET", f"/api/missions/{mission}/history")
    assert code == 200 and any(c["task_id"] == "centered_mod" for c in hist["commits"]), (code, hist)
    code, mbox = req("GET", f"/api/missions/{mission}/history.mbox", raw=True)
    assert code == 200
    code, seed = req("GET", f"/api/missions/{mission}/bundle.tar.gz?base=seed", raw=True)
    assert code == 200
    code, live = req("GET", f"/api/missions/{mission}/bundle.tar.gz", raw=True)
    assert code == 200
    with tempfile.TemporaryDirectory() as tmp:
        for name, data in (("seed", seed), ("live", live)):
            os.makedirs(os.path.join(tmp, name))
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
                tf.extractall(os.path.join(tmp, name), filter="data")
        with open(os.path.join(tmp, "history.mbox"), "wb") as f:
            f.write(mbox)
        subprocess.run(["git", "-c", "user.name=e2e", "-c", "user.email=e2e@localhost",
                        "am", "-q", os.path.join(tmp, "history.mbox")],
                       cwd=os.path.join(tmp, "seed"), check=True)
        log = subprocess.check_output(["git", "log", "--format=%an|%s"],
                                      cwd=os.path.join(tmp, "seed"), text=True)
        assert "alice|" in log and "verify centered_mod" in log, log
        diff = subprocess.run(["diff", "-r", "-x", ".git", os.path.join(tmp, "seed"),
                               os.path.join(tmp, "live")], capture_output=True, text=True)
        assert diff.returncode == 0, diff.stdout[-2000:]
    ok("seed bundle + history.mbox (git am) rebuilds the live mission, with authors")

    code, stats = req("GET", "/api/stats")
    assert code == 200 and stats["all_time"]["registered"] >= 3, (code, stats)
    assert stats["all_time"]["claimed"] >= 1 and stats["all_time"]["verified"] >= 2, stats
    ok(f"funnel stats: {stats['all_time']}")
    print("\nAll end-to-end checks passed.")


if __name__ == "__main__":
    main()
