#!/usr/bin/env python3
"""
End-to-end test of the Sunstead Lean 4 hub (Cloudflare Worker + Durable Object +
Lean 4 verifier container), using only the public HTTP protocol from /join.txt.

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
import threading
import time
import urllib.error
import urllib.request

BASE = os.environ.get("SUNSTEAD_URL", "http://localhost:5173").rstrip("/")
if "sunstead.org" in BASE and os.environ.get("SUNSTEAD_E2E_ALLOW_PROD") != "1":
    sys.exit("refusing to run e2e against production (set SUNSTEAD_E2E_ALLOW_PROD=1 to override)")

RUN = f"{random.randrange(16**6):06x}"


def req(method, path, body=None, key=None, raw=False):
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"User-Agent": "sunstead-e2e/0.3"}
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
    return res["handle"], res["api_key"]


def extract(tf, dest):
    if hasattr(tarfile, "data_filter"):  # Python >= 3.12 (and security backports)
        tf.extractall(dest, filter="data")
    else:  # older Python; the bundle comes from the hub under test
        tf.extractall(dest)


def make_patch(mission_id, edits):
    code, data = req("GET", f"/api/missions/{mission_id}/bundle.tar.gz", raw=True)
    assert code == 200, f"bundle download failed: {code}"
    with tempfile.TemporaryDirectory() as tmp:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
            extract(tf, tmp)
        for rel, content in edits.items():
            with open(os.path.join(tmp, rel), "w", encoding="utf-8") as f:
                f.write(content)
        return subprocess.check_output(["git", "diff"], cwd=tmp, text=True)


def submit(mission, task, key, edits, expect_in_patch=None):
    patch = make_patch(mission, edits)
    if expect_in_patch is not None:
        assert expect_in_patch in patch, f"expected {expect_in_patch!r} in patch:\n{patch}"
    return req("POST", f"/api/missions/{mission}/tasks/{task}/submit", {"patch": patch}, key=key)


def ok(msg):
    print(f"  [PASS] {msg}")


class SseCollector:
    """Background reader for GET /api/events so we can assert SSE events like lease_released."""

    def __init__(self):
        self.events = []
        self.ready = threading.Event()
        self.stop_flag = threading.Event()
        self._resp = None
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self._thread.start()
        assert self.ready.wait(timeout=10), "SSE stream did not connect within 10s"

    def _run(self):
        r = urllib.request.Request(BASE + "/api/events", headers={"User-Agent": "sunstead-e2e/0.3"})
        try:
            with urllib.request.urlopen(r, timeout=60) as resp:
                self._resp = resp
                event_name = None
                for raw_line in resp:
                    if self.stop_flag.is_set():
                        break
                    line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
                    if line.startswith(": connected"):
                        self.ready.set()
                    elif line.startswith("event: "):
                        event_name = line[len("event: "):]
                    elif line.startswith("data: "):
                        try:
                            payload = json.loads(line[len("data: "):])
                        except Exception:
                            payload = {}
                        self.events.append((event_name, payload))
                        event_name = None
        except Exception:
            pass

    def wait_for(self, kind, predicate, timeout=5.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for ev_kind, payload in list(self.events):
                if ev_kind == kind and predicate(payload):
                    return payload
            time.sleep(0.05)
        raise AssertionError(f"did not observe SSE event {kind!r}; saw {self.events}")

    def close(self):
        self.stop_flag.set()
        if self._resp is not None:
            try:
                self._resp.close()
            except Exception:
                pass


MU_400_WITH_COMMENT = """import SoundnessBound.Spec

namespace SoundnessBound

-- temporary note that will be deleted in the next tightening patch
def claimedMultiUserFactor : Nat := 400

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

MU_300_NO_COMMENT = MU_400_WITH_COMMENT.replace(
    "-- temporary note that will be deleted in the next tightening patch\n", ""
).replace(":= 400", ":= 300")

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
  sorry

end MetaComplexity
"""


def main():
    print(f"==> Testing Sunstead Lean 4 hub at {BASE} (run {RUN})")

    code, health = req("GET", "/api/health")
    assert code == 200 and health.get("ok") is True, health
    ok("/api/health")

    code, missions = req("GET", "/api/missions")
    assert code == 200
    by_id = {m["id"]: m for m in missions["missions"]}
    expected_ids = {
        "tier1-metacomplexity-dag",
        "tier1-crypto-algebra-dag",
        "tier2-soundness-bound",
        "tier2-coding-bounds",
    }
    assert set(by_id.keys()) == expected_ids, by_id.keys()
    assert by_id["tier2-soundness-bound"]["demo"] is True, by_id["tier2-soundness-bound"]
    assert by_id["tier1-metacomplexity-dag"]["demo"] is False, by_id["tier1-metacomplexity-dag"]
    ok(f"/api/missions lists {len(by_id)} Lean 4 missions with demo flags")

    code, join_txt = req("GET", "/join.txt")
    assert code == 200 and "contributors/register" in join_txt and "lake build" in join_txt
    assert "Verus" not in join_txt and "Rust target files" not in join_txt
    ok("/join.txt (Lean-only, documents native Lean and Docker)")

    # Identity is required for claims and submissions.
    code, res = req("POST", "/api/missions/tier1-metacomplexity-dag/tasks/decoder_injective/claim", {})
    assert code == 401, (code, res)
    ok("anonymous claim rejected (401)")

    alice_handle, alice = register("alice-lean")
    bob_handle, bob = register("bob-lean")
    _, mallory = register("mallory")
    ok("registered 3 contributors")

    # Policy gate: frozen spec edits are rejected before any container runs.
    code, res = submit("tier1-metacomplexity-dag", "decoder_injective", mallory,
                       {"MetaComplexity/Spec.lean": "-- tampered\n"})
    assert code == 422 and "frozen" in json.dumps(res), (code, res)
    ok("frozen-path tampering rejected (422)")

    # Claim -> contention -> release -> SSE `lease_released` -> re-claim.
    sse = SseCollector()
    sse.start()
    try:
        code, res = req("POST", "/api/missions/tier1-metacomplexity-dag/tasks/decoder_injective/claim", {}, key=alice)
        assert code == 200 and res.get("claimed") is True, (code, res)
        code, res = req("POST", "/api/missions/tier1-metacomplexity-dag/tasks/decoder_injective/claim", {}, key=bob)
        assert code == 409, (code, res)
        code, res = req("POST", "/api/missions/tier1-metacomplexity-dag/tasks/decoder_injective/release", {}, key=alice)
        assert code == 200 and res.get("released") is True, (code, res)
        sse.wait_for(
            "lease_released",
            lambda ev: ev.get("mission_id") == "tier1-metacomplexity-dag"
            and ev.get("task_id") == "decoder_injective"
            and ev.get("contributor") == alice_handle,
        )
        code, res = req("POST", "/api/missions/tier1-metacomplexity-dag/tasks/decoder_injective/claim", {}, key=bob)
        assert code == 200 and res.get("claimed") is True, (code, res)
        ok("lease claimed, second claimant blocked, released with SSE lease_released, re-claimed")
    finally:
        sse.close()

    # Tier 1: sorryAx proof rejected by the kernel axiom check; string-comment hiding rejected by lint.
    code, res = submit("tier1-metacomplexity-dag", "pigeonhole_fin", mallory,
                       {"MetaComplexity/Pigeonhole.lean": PIGEONHOLE.replace(":= by\n  sorry", ":=\n  sorryAx _ false")})
    assert code == 422 and "sorryAx" in json.dumps(res), (code, res)
    ok("sorryAx proof rejected by the kernel axiom check")

    code, res = submit("tier1-metacomplexity-dag", "decoder_injective", mallory,
                       {"MetaComplexity/DecoderInjective.lean": DECODER + '\ndef s := "--" ; #eval IO.println "pwn"\n'})
    assert code == 422, (code, res)
    ok("string-literal comment hiding rejected")

    # Honest Tier 1 proof accepted with 150 points.
    code, res = submit("tier1-metacomplexity-dag", "decoder_injective", bob,
                       {"MetaComplexity/DecoderInjective.lean": DECODER})
    assert code == 200 and res.get("accepted") is True and res.get("points_awarded") == 150, (code, res)
    ok(f"Tier 1 decoder_injective accepted ({res.get('verify_ms')} ms, 150 pts)")

    # Re-submitting an already-verified DAG task is rejected fast (409) before waking a container.
    code, res = submit("tier1-metacomplexity-dag", "decoder_injective", alice,
                       {"MetaComplexity/DecoderInjective.lean": DECODER + "\n-- extra\n"})
    assert code == 409, (code, res)
    ok("already-verified DAG task rejected before container wakeup (409)")

    # Tier 2 demo hill-climb: 1000 -> 400 (adds `-- ` comment) -> 300 (DELETES `-- ` comment,
    # producing `--- ` in the unified diff hunk!). Both earn 0 points because demo=true.
    code, res = submit("tier2-soundness-bound", "tighten_multi_user_bound", bob,
                       {"SoundnessBound/MultiUserBound.lean": MU_400_WITH_COMMENT})
    assert code == 200 and res.get("accepted") is True and res.get("score") == 400.0, (code, res)
    assert res.get("points_awarded") == 0, res
    ok("Tier 2 demo 1000 -> 400 accepted (0 demo points)")

    code, res = submit(
        "tier2-soundness-bound",
        "tighten_multi_user_bound",
        bob,
        {"SoundnessBound/MultiUserBound.lean": MU_300_NO_COMMENT},
        expect_in_patch="--- temporary note that will be deleted in the next tightening patch",
    )
    assert code == 200 and res.get("accepted") is True and res.get("score") == 300.0, (code, res)
    assert res.get("points_awarded") == 0, res
    ok("Tier 2 demo 400 -> 300 deleting a `-- ` Lean comment accepted (0 demo points)")

    code, res = submit("tier2-soundness-bound", "tighten_multi_user_bound", alice,
                       {"SoundnessBound/MultiUserBound.lean": MU_300_NO_COMMENT.replace(":= 300", ":= 500")})
    assert code == 422 and "strictly improve" in json.dumps(res), (code, res)
    ok("Tier 2 regression rejected")

    # Leaderboard: bob has 150 pts from Tier 1 and 0 hill-climb crowns from demo Tier 2.
    code, board = req("GET", "/api/leaderboard")
    assert code == 200
    bob_row = next((e for e in board["leaderboard"] if e["contributor"] == bob_handle), None)
    assert bob_row is not None and bob_row["points"] == 150 and bob_row["active_records"] == 0, bob_row
    ok(f"leaderboard verified (demo mission awarded 0 points and 0 crowns: {bob_row})")

    # Exact `how_to_rebuild` command rebuilds the live mission with attributed commits!
    for mission, expect_subj in (
        ("tier1-metacomplexity-dag", "verify decoder_injective"),
        ("tier2-soundness-bound", "verify tighten_multi_user_bound"),
    ):
        code, hist = req("GET", f"/api/missions/{mission}/history")
        assert code == 200 and len(hist["commits"]) >= 1, (code, hist)
        cmd = hist["how_to_rebuild"]
        assert "git init" not in cmd, f"how_to_rebuild must not re-init git: {cmd}"
        assert "bundle.tar.gz?base=seed" in cmd and "history.mbox | git am" in cmd, cmd

        code, live = req("GET", f"/api/missions/{mission}/bundle.tar.gz", raw=True)
        assert code == 200
        with tempfile.TemporaryDirectory() as tmp:
            rebuilt_dir = os.path.join(tmp, "rebuilt")
            live_dir = os.path.join(tmp, "live")
            os.makedirs(rebuilt_dir)
            os.makedirs(live_dir)
            with tarfile.open(fileobj=io.BytesIO(live), mode="r:gz") as tf:
                extract(tf, live_dir)
            env = os.environ.copy()
            env.setdefault("GIT_COMMITTER_NAME", "e2e")
            env.setdefault("GIT_COMMITTER_EMAIL", "e2e@localhost")
            subprocess.run(
                ["bash", "-euo", "pipefail", "-c", cmd.replace("<hub>", BASE)],
                cwd=rebuilt_dir,
                env=env,
                check=True,
            )
            log = subprocess.check_output(["git", "log", "--format=%an|%s"], cwd=rebuilt_dir, text=True)
            assert f"bob-lean|" in log and expect_subj in log, log
            diff = subprocess.run(
                ["diff", "-r", "-x", ".git", rebuilt_dir, live_dir],
                capture_output=True,
                text=True,
            )
            assert diff.returncode == 0, diff.stdout[-2000:]
    ok("exact `how_to_rebuild` command rebuilds live Lean missions with authors")

    code, stats = req("GET", "/api/stats")
    assert code == 200 and stats["all_time"]["registered"] >= 3, (code, stats)
    assert stats["all_time"]["claimed"] >= 1 and stats["all_time"]["verified"] >= 1, stats
    ok(f"funnel stats: {stats['all_time']}")
    print("\nAll end-to-end checks passed.")


if __name__ == "__main__":
    main()
