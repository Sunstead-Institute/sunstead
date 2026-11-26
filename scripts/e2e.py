#!/usr/bin/env python3
"""
End-to-end test of the Sunstead Lean 4 hub (Cloudflare Worker + Durable Object
+ Lean 4 verifier container), using only the public HTTP protocol from /join.txt.

    cd cloudflare && npm run dev          # local dev server (needs Docker)
    SUNSTEAD_URL=http://localhost:5173 python3 scripts/e2e.py

Derives expected missions dynamically from `missions/*/sunstead.json` and runs
strictly non-destructive verification checks (no fake proofs or upstream spoilers).
Never point this at production: it registers contributors, claims/releases leases,
and submits rejected verification patches.
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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MISSIONS_DIR = os.path.join(ROOT, "missions")

BASE = os.environ.get("SUNSTEAD_URL", "http://localhost:5173").rstrip("/")
if "sunstead.org" in BASE and os.environ.get("SUNSTEAD_E2E_ALLOW_PROD") != "1":
    sys.exit("refusing to run e2e against production (set SUNSTEAD_E2E_ALLOW_PROD=1 to override)")

RUN = f"{random.randrange(16**6):06x}"


def load_local_manifests():
    manifests = {}
    for entry in sorted(os.listdir(MISSIONS_DIR)):
        manifest_path = os.path.join(MISSIONS_DIR, entry, "sunstead.json")
        if os.path.isfile(manifest_path):
            with open(manifest_path, encoding="utf-8") as f:
                m = json.load(f)
            manifests[m["id"]] = m
    assert manifests, f"no missions/*/sunstead.json found under {MISSIONS_DIR}"
    return manifests


def req(method, path, body=None, key=None, raw=False):
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"User-Agent": "sunstead-e2e/0.5"}
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
    assert code == 200, f"bundle download failed for {mission_id}: {code}"
    with tempfile.TemporaryDirectory() as tmp:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
            extract(tf, tmp)
        for rel, content in edits.items():
            dst = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8") as f:
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
        r = urllib.request.Request(BASE + "/api/events", headers={"User-Agent": "sunstead-e2e/0.5"})
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


PNT_SORRYAX = """import PntFoundations.Spec

open ArithmeticFunction

namespace PntFoundations

lemma isCompletelyMultiplicative_liouville :
    IsCompletelyMultiplicative (liouville : ArithmeticFunction ℝ) :=
  sorryAx _ false

end PntFoundations
"""

ARKLIB_SORRYAX = """import ArkLibNearCapacity.Spec

open scoped NNReal

namespace ArkLibNearCapacity

theorem near_capacity_prime_supply (c : ℝ≥0) (hc : 0 < c) : NearCapacityPrimeSupply c :=
  sorryAx _ false

end ArkLibNearCapacity
"""


def pick_open_frontier_task(by_id, local_manifests):
    """Pick a live open frontier task, preferring fast v4.36.0 standalone DAG missions."""
    preferred = [
        "pnt-analytic-foundations",
        "arklib-near-capacity-primes",
        "ieantn-chebyshev-kernel",
        "matrix-rank444-f2",
    ]
    ordered = [mid for mid in preferred if mid in by_id] + [
        mid for mid in sorted(by_id) if mid not in preferred
    ]
    for mid in ordered:
        frontier = by_id[mid].get("frontier_task_ids") or []
        if frontier:
            tid = frontier[0]
            task_def = next(t for t in local_manifests[mid]["tasks"] if t["id"] == tid)
            return mid, tid, task_def
    raise AssertionError("no open frontier task found in any active mission")


def main():
    local_manifests = load_local_manifests()
    print(f"==> Testing Sunstead Lean 4 hub at {BASE} (run {RUN}, {len(local_manifests)} local missions)")

    code, health = req("GET", "/api/health")
    assert code == 200 and health.get("ok") is True, health
    ok("/api/health")

    code, missions = req("GET", "/api/missions")
    assert code == 200, (code, missions)
    by_id = {m["id"]: m for m in missions["missions"]}
    assert set(by_id.keys()) == set(local_manifests.keys()), (
        f"mission mismatch: hub={sorted(by_id.keys())} local={sorted(local_manifests.keys())}"
    )
    assert "onboarding-sandbox" not in by_id, "retired onboarding-sandbox must not appear in /api/missions"
    for mid, manifest in local_manifests.items():
        live = by_id[mid]
        assert live["demo"] is bool(manifest.get("demo", False)), (mid, live)
        assert live["mode"] == manifest["mode"], (mid, live)
        if manifest.get("upstream"):
            assert live["upstream"]["repo"] == manifest["upstream"]["repo"], (mid, live)
            assert live["upstream"]["commit"] == manifest["upstream"]["commit"], (mid, live)
    ok(f"/api/missions matches all {len(by_id)} manifests from missions/*/sunstead.json with upstream provenance")

    code, join_txt = req("GET", "/join.txt")
    assert code == 200 and "contributors/register" in join_txt
    assert "lake exe cache get" in join_txt
    assert "onboarding-sandbox" not in join_txt, "retired onboarding-sandbox must not appear in /join.txt"
    assert "Verus" not in join_txt and "Rust target files" not in join_txt
    for mid in local_manifests:
        assert mid in join_txt, f"active mission {mid!r} missing from /join.txt"
    ok("/join.txt lists all active missions without retired sandbox references")

    code, about_html = req("GET", "/what-is-this")
    assert code == 200 and "What is Sunstead?" in about_html, code
    ok("/what-is-this explainer page served")

    probe_mission, probe_task, probe_task_def = pick_open_frontier_task(by_id, local_manifests)
    probe_target = probe_task_def["target_files"][0]
    probe_manifest = local_manifests[probe_mission]
    frozen_sample = next(
        (p for p in ("UPSTREAM.json", "sunstead.json", "lean-toolchain") if p in probe_manifest["frozen_paths"]),
        probe_manifest["frozen_paths"][0],
    )

    # Identity is required for claims and submissions.
    code, res = req("POST", f"/api/missions/{probe_mission}/tasks/{probe_task}/claim", {})
    assert code == 401, (code, res)
    ok(f"anonymous claim rejected (401) on {probe_mission}/{probe_task}")

    alice_handle, alice = register("alice-lean")
    bob_handle, bob = register("bob-lean")
    _, mallory = register("mallory")
    ok("registered 3 contributors")

    # Profile endpoint: strict handle validation & proof-gated public links.
    code, me = req("GET", "/api/me", key=alice)
    assert code == 200 and me["links_public"] is False and me["non_demo_verified"] == 0, (code, me)
    code, res = req("PATCH", "/api/me", {"github": "https://github.com/octocat"}, key=alice)
    assert code == 400, (code, res)
    code, me = req("PATCH", "/api/me", {"github": "octocat", "x": "octo_x"}, key=alice)
    assert code == 200 and me["contributor"]["github"] == "octocat" and me["links_public"] is False, (code, me)
    code, pub = req("GET", f"/api/contributors/{alice_handle}")
    assert code == 200 and pub["contributor"]["github"] is None and pub["contributor"]["social_links"] == [], (code, pub)
    ok("/api/me validates handles strictly and gates public social links until >= 1 non-demo proof")

    # Policy gate: frozen spec edits are rejected fast (422) before waking any container.
    code, res = submit(probe_mission, probe_task, mallory, {frozen_sample: "-- tampered\n"})
    assert code == 422 and "frozen" in json.dumps(res) and res.get("stage") == "patch", (code, res)
    ok(f"frozen-path tampering rejected fast (422, stage=patch) on {probe_mission}:{frozen_sample}")

    # Claim -> 409 contention -> release -> SSE `lease_released` -> re-claim -> clean release.
    sse = SseCollector()
    sse.start()
    try:
        code, res = req("POST", f"/api/missions/{probe_mission}/tasks/{probe_task}/claim", {}, key=alice)
        assert code == 200 and res.get("claimed") is True, (code, res)
        code, res = req("POST", f"/api/missions/{probe_mission}/tasks/{probe_task}/claim", {}, key=bob)
        assert code == 409, (code, res)
        code, res = req("POST", f"/api/missions/{probe_mission}/tasks/{probe_task}/release", {}, key=alice)
        assert code == 200 and res.get("released") is True, (code, res)
        sse.wait_for(
            "lease_released",
            lambda ev: ev.get("mission_id") == probe_mission
            and ev.get("task_id") == probe_task
            and ev.get("contributor") == alice_handle,
        )
        code, res = req("POST", f"/api/missions/{probe_mission}/tasks/{probe_task}/claim", {}, key=bob)
        assert code == 200 and res.get("claimed") is True, (code, res)
        code, res = req("POST", f"/api/missions/{probe_mission}/tasks/{probe_task}/release", {}, key=bob)
        assert code == 200 and res.get("released") is True, (code, res)
        ok(f"lease claimed, second claimant blocked (409), released with SSE lease_released, re-claimed & released")
    finally:
        sse.close()

    # Read-only single-request task files inspection endpoint.
    code, tfiles = req("GET", f"/api/missions/{probe_mission}/tasks/{probe_task}/files")
    assert code == 200, (code, tfiles)
    assert tfiles["task_id"] == probe_task and probe_target in tfiles["target_files"], tfiles
    assert tfiles["frozen_files"], tfiles
    code, res = req("GET", f"/api/missions/{probe_mission}/tasks/no-such-task/files")
    assert code == 404, (code, res)
    ok("task-files endpoint returns target_files + frozen_files without waking verifier; 404 on unknown task")

    # Non-destructive verifier checks: lint rejection (comment-hide) via the real container.
    target_src = tfiles["target_files"][probe_target]
    code, res = submit(
        probe_mission,
        probe_task,
        mallory,
        {probe_target: target_src + '\ndef _e2e_s : String := "--" ; #eval IO.println "pwn"\n'},
    )
    assert code == 422 and res.get("stage") == "lint", (code, res)
    ok(f"verifier container rejected string-literal comment hiding (422, stage=lint) on {probe_mission}/{probe_task}")

    # Non-destructive verifier check: sorryAx rejected by kernel axiom check on a live Mathlib mission.
    if "pnt-analytic-foundations" in by_id and "is_completely_multiplicative_liouville" in (
        by_id["pnt-analytic-foundations"].get("frontier_task_ids") or []
    ):
        code, res = submit(
            "pnt-analytic-foundations",
            "is_completely_multiplicative_liouville",
            mallory,
            {"PntFoundations/LiouvilleMult.lean": PNT_SORRYAX},
        )
        assert code == 422 and "sorryAx" in json.dumps(res), (code, res)
        ok("upstream Mathlib mission sorryAx rejected by Lean 4.36.0 kernel axiom check (pnt-analytic-foundations)")
    elif "arklib-near-capacity-primes" in by_id and "near_capacity_prime_supply" in (
        by_id["arklib-near-capacity-primes"].get("frontier_task_ids") or []
    ):
        code, res = submit(
            "arklib-near-capacity-primes",
            "near_capacity_prime_supply",
            mallory,
            {"ArkLibNearCapacity/PrimeSupply.lean": ARKLIB_SORRYAX},
        )
        assert code == 422 and "sorryAx" in json.dumps(res), (code, res)
        ok("upstream Mathlib mission sorryAx rejected by Lean 4.36.0 kernel axiom check (arklib-near-capacity-primes)")

    # Non-destructive happy-path kernel-replay check on `matrix-rank444-f2`:
    # submitting a comment-only edit of the published r=47 certificate runs full
    # Lean 4.36.0 `decide +kernel` verification (ok=true, score=47) inside the
    # container and is cleanly rejected by the hub's strict-improvement check
    # without mutating mission state.
    if "matrix-rank444-f2" in by_id:
        code, rank_files = req("GET", "/api/missions/matrix-rank444-f2/tasks/reduce_rank/files")
        assert code == 200, (code, rank_files)
        cert_src = rank_files["target_files"]["Rank444/Certificate.lean"]
        code, res = submit(
            "matrix-rank444-f2",
            "reduce_rank",
            bob,
            {"Rank444/Certificate.lean": cert_src + f"\n-- e2e non-destructive kernel check {RUN}\n"},
        )
        assert code == 422 and "does not strictly improve on best" in json.dumps(res), (code, res)
        ok("non-destructive full kernel-replay check passed on matrix-rank444-f2 (verified r=47, strict-improvement guard held)")

    # Mission history & seed bundle contract (contains `.git` + `sunstead.json` for `git am`).
    code, hist = req("GET", f"/api/missions/{probe_mission}/history")
    assert code == 200 and "bundle.tar.gz?base=seed" in hist["how_to_rebuild"], (code, hist)
    assert "git init" not in hist["how_to_rebuild"], hist["how_to_rebuild"]
    code, mbox = req("GET", f"/api/missions/{probe_mission}/history.mbox", raw=True)
    assert code == 200, code
    code, seed_tar = req("GET", f"/api/missions/{probe_mission}/bundle.tar.gz?base=seed", raw=True)
    assert code == 200, code
    with tarfile.open(fileobj=io.BytesIO(seed_tar), mode="r:gz") as tf:
        names = tf.getnames()
    assert any(n.endswith("sunstead.json") for n in names), names[:20]
    assert any(".git/" in n or n.endswith(".git") for n in names), names[:20]
    ok(f"history, history.mbox, and seed bundle.tar.gz?base=seed verified for {probe_mission}")

    # Public proof ledger endpoints & validation.
    code, ledger = req("GET", "/api/proofs?limit=50")
    assert code == 200 and isinstance(ledger.get("proofs"), list), (code, ledger)
    if ledger["proofs"]:
        entry = ledger["proofs"][0]
        code, perm = req("GET", "/api/proofs/" + entry["proof_id"])
        assert code == 200 and perm["patch_sha256"] == entry["patch_sha256"], (code, perm)
        code, page = req("GET", "/proofs/" + entry["proof_id"], raw=True)
        assert code == 200 and b'id="ledger-root"' in page and b'id="verify-yourself"' in page, code
        for e in ledger["proofs"]:
            vc = e.get("verify_command")
            assert vc is None or vc.split("verify.py ", 1)[1].startswith(e["proof_id"]), e
        # The public verifier's own integrity check (sha256(patch) == proof id) agrees with the hub.
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import sunstead_verify
        sunstead_verify.load_public_proof(BASE, entry["proof_id"])
    code, script = req("GET", "/verify.py", raw=True)
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sunstead_verify.py"), "rb") as f:
        assert code == 200 and script == f.read(), "served /verify.py must be scripts/sunstead_verify.py byte for byte"
    code, res = req("GET", "/api/proofs/" + "0" * 64)
    assert code == 404, (code, res)
    code, res = req("GET", "/api/proofs/not-a-hash")
    assert code == 400, (code, res)
    code, res = req("GET", "/api/missions/no-such-mission/tasks/x/proof")
    assert code == 404, (code, res)
    ok("proof ledger endpoints respond cleanly and reject invalid/missing proof IDs")

    code, board = req("GET", "/api/leaderboard")
    assert code == 200 and isinstance(board.get("leaderboard"), list), (code, board)
    ok(f"/api/leaderboard returned {len(board['leaderboard'])} entries")

    code, stats = req("GET", "/api/stats")
    assert code == 200 and stats["all_time"]["registered"] >= 3, (code, stats)
    assert stats["all_time"]["claimed"] >= 1 and stats["all_time"]["submissions"] >= 1, stats
    ok(f"funnel stats: {stats['all_time']}")
    print("\nAll end-to-end checks passed.")


if __name__ == "__main__":
    main()
