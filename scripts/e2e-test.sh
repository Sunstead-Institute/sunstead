#!/usr/bin/env python3
"""
End-to-end verification of Sunstead Hub using ONLY the public `/join.txt` HTTP protocol.
Tests all 3 expanded launch missions:
  1. /api/health & /join.txt (15 total tasks across Tiers 1-3)
  2. Policy gate: frozen_paths tampering rejected BEFORE Docker runs
  3. Tier 3 (7-node FIPS 204 ML-DSA Rust): constant-time hygiene rejection +
     real verified submissions for centered_mod, montgomery_reduce, power2round
  4. Tier 2 (2-track Lean 4 hill-climb): multi-user bound 1000 -> 300 accepted,
     regression 500 rejected; folding bound 1600 -> 600 accepted
  5. Tier 1 (6-node Lean 4 DAG): soft-lease claim + decoder_injective + pigeonhole_fin
     unlocking bijection_card_eq, incompressibility_theorem, non_surjective_decoder!
"""
import io
import json
import os
import subprocess
import tarfile
import tempfile
import urllib.error
import urllib.request

BASE = os.environ.get("SUNSTEAD_URL", "http://127.0.0.1:8787").rstrip("/")


def req(method, path, body=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Content-Type": "application/json"} if body is not None else {}
    r = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=180) as resp:
            raw = resp.read()
            ctype = resp.headers.get("Content-Type", "")
            return resp.status, (json.loads(raw) if "json" in ctype else raw)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw.decode("utf-8", errors="replace")


def download_bundle(mission_id, dest_dir):
    status, data = req("GET", f"/api/missions/{mission_id}/bundle.tar.gz")
    assert status == 200, f"bundle download failed: {status}"
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tf:
        tf.extractall(dest_dir)


def make_patch(mission_id, edits: dict) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        download_bundle(mission_id, tmp)
        for rel, content in edits.items():
            full = os.path.join(tmp, rel)
            with open(full, "w", encoding="utf-8") as f:
                f.write(content)
        return subprocess.check_output(["git", "diff"], cwd=tmp, text=True)


def main():
    print(f"==> Testing Sunstead Hub at {BASE}")

    # 1. Health & /join.txt & 15 total tasks
    code, health = req("GET", "/api/health")
    assert code == 200 and health.get("docker_verifier_ready") is True, health
    print("  [PASS] /api/health -> docker_verifier_ready=true")

    code, missions = req("GET", "/api/missions")
    assert code == 200
    total = sum(m["total_tasks"] for m in missions["missions"])
    assert total == 15, f"expected 15 total tasks, got {total}"
    print("  [PASS] /api/missions loaded 3 launch arenas (15 total tasks)")

    code, join_txt = req("GET", "/join.txt")
    assert code == 200 and b"best: 1000, minimize" in join_txt and b"docker cp" in join_txt
    print("  [PASS] /join.txt shows inline hill-climb best scores & portable docker cp")

    # 2. Adversarial tamper test: touching frozen src/spec.rs MUST fail before Docker (HTTP 422)
    tamper_patch = make_patch("tier3-mldsa-arith", {"src/spec.rs": "pub const Q: i32 = 1;\n"})
    code, res = req(
        "POST",
        "/api/missions/tier3-mldsa-arith/tasks/centered_mod/submit",
        {"contributor": "mallory-bot", "patch": tamper_patch},
    )
    assert code == 422 and "frozen" in str(res).lower(), (code, res)
    print("  [PASS] Frozen-path tampering rejected before Docker (HTTP 422)")

    # 3a. Tier 3 hygiene test: branching `if` rejected
    branchy_patch = make_patch(
        "tier3-mldsa-arith",
        {
            "src/centered_mod.rs": (
                "use crate::spec::{HALF_Q, Q};\n"
                "pub fn centered_mod(a: i32) -> i32 { if a > HALF_Q { a - Q } else { a } }\n"
            )
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier3-mldsa-arith/tasks/centered_mod/submit",
        {"contributor": "naive-agent", "patch": branchy_patch},
    )
    assert code == 422 and "branching" in str(res).lower(), (code, res)
    print("  [PASS] Tier 3 constant-time hygiene rejected branching `if`")

    # 3b. Tier 3 real FIPS 204 proofs: centered_mod, montgomery_reduce, power2round
    centered_patch = make_patch(
        "tier3-mldsa-arith",
        {
            "src/centered_mod.rs": (
                "use crate::spec::{HALF_Q, Q};\n"
                "pub fn centered_mod(a: i32) -> i32 {\n"
                "    let diff = a - (HALF_Q + 1);\n"
                "    let mask = !(diff >> 31);\n"
                "    a - (Q & mask)\n"
                "}\n"
            )
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier3-mldsa-arith/tasks/centered_mod/submit",
        {"contributor": "alice-rust-agent", "patch": centered_patch},
    )
    assert code == 200 and res.get("accepted") is True, (code, res)
    print(f"  [PASS] Tier 3 centered_mod ACCEPTED ({res['verify_ms']}ms)")

    mont_patch = make_patch(
        "tier3-mldsa-arith",
        {
            "src/montgomery.rs": (
                "use crate::spec::{Q, QINV};\n"
                "pub fn montgomery_reduce(a: i64) -> i32 {\n"
                "    let t = (a as i32).wrapping_mul(QINV);\n"
                "    ((a - (t as i64) * (Q as i64)) >> 32) as i32\n"
                "}\n"
            )
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier3-mldsa-arith/tasks/montgomery_reduce/submit",
        {"contributor": "alice-rust-agent", "patch": mont_patch},
    )
    assert code == 200 and res.get("accepted") is True, (code, res)
    print(f"  [PASS] Tier 3 montgomery_reduce ACCEPTED ({res['verify_ms']}ms)")

    p2r_patch = make_patch(
        "tier3-mldsa-arith",
        {
            "src/power2round.rs": (
                "use crate::spec::{D_BITS, HALF_TWO_D};\n"
                "pub fn power2round(r: i32) -> (i32, i32) {\n"
                "    let r1 = (r + HALF_TWO_D - 1) >> D_BITS;\n"
                "    let r0 = r - (r1 << D_BITS);\n"
                "    (r1, r0)\n"
                "}\n"
            )
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier3-mldsa-arith/tasks/power2round/submit",
        {"contributor": "alice-rust-agent", "patch": p2r_patch},
    )
    assert code == 200 and res.get("accepted") is True, (code, res)
    print(f"  [PASS] Tier 3 power2round (all 8.38M residues) ACCEPTED ({res['verify_ms']}ms)")

    # 4a. Tier 2 Multi-User Hill-Climb: tighten 1000 -> 300 in Lean 4
    mu_300_patch = make_patch(
        "tier2-soundness-bound",
        {
            "SoundnessBound/MultiUserBound.lean": """import SoundnessBound.Spec

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
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier2-soundness-bound/tasks/tighten_multi_user_bound/submit",
        {"contributor": "bob-lean-prover", "patch": mu_300_patch},
    )
    assert code == 200 and res.get("accepted") is True and res.get("score") == 300.0, (code, res)
    print(f"  [PASS] Tier 2 multi-user bound 1000 -> 300 ACCEPTED ({res['verify_ms']}ms)")

    # 4b. Tier 2 Regression check: C = 500 (worse than 300) MUST be rejected
    mu_500_patch = make_patch(
        "tier2-soundness-bound",
        {
            "SoundnessBound/MultiUserBound.lean": mu_300_patch.replace("300", "500")
            if False
            else """import SoundnessBound.Spec

namespace SoundnessBound

def claimedMultiUserFactor : Nat := 500

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
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier2-soundness-bound/tasks/tighten_multi_user_bound/submit",
        {"contributor": "carol-slow-agent", "patch": mu_500_patch},
    )
    assert code == 422 and "does not strictly improve" in str(res).lower(), (code, res)
    print("  [PASS] Tier 2 regression C = 500 rejected by sunstead-core")

    # 4c. Tier 2 Folding bound hill-climb: 1600 -> 600 in Lean 4
    fold_600_patch = make_patch(
        "tier2-soundness-bound",
        {
            "SoundnessBound/FoldingBound.lean": """import SoundnessBound.Spec

namespace SoundnessBound

def claimedFoldingFactor : Nat := 600

theorem folding_bound :
    ∀ d r : Nat, d ≥ 1 → r ≥ 1 →
      100 * foldingError d r ≤ claimedFoldingFactor * ((d + r) * (d + r)) := by
  intro d r hd hr
  unfold foldingError claimedFoldingFactor
  have hdiv2 : 2 * ((d * (d - 1)) / 2) ≤ d * (d - 1) := Nat.mul_div_le _ 2
  have hsub : d * (d - 1) ≤ d * d := Nat.mul_le_mul_left d (Nat.sub_le d 1)
  have hexp : (d + r) * (d + r) = d * d + 2 * (d * r) + r * r := by
    rw [Nat.add_mul, Nat.mul_add, Nat.mul_add, Nat.mul_comm r d]
    omega
  have hd2 : d ≤ d * d := by
    calc d = d * 1 := (Nat.mul_one d).symm
      _ ≤ d * d := Nat.mul_le_mul_left d hd
  have hr2 : r ≤ r * r := by
    calc r = r * 1 := (Nat.mul_one r).symm
      _ ≤ r * r := Nat.mul_le_mul_left r hr
  omega

end SoundnessBound
"""
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier2-soundness-bound/tasks/tighten_folding_bound/submit",
        {"contributor": "delta-sharp-prover", "patch": fold_600_patch},
    )
    assert code == 200 and res.get("accepted") is True and res.get("score") == 600.0, (code, res)
    print(f"  [PASS] Tier 2 folding bound 1600 -> 600 ACCEPTED ({res['verify_ms']}ms)")

    # 5a. Tier 1 DAG: claim soft lease + verify decoder_injective + pigeonhole_fin
    code, claim = req(
        "POST",
        "/api/missions/tier1-metacomplexity-dag/tasks/decoder_injective/claim",
        {"contributor": "euler-lean-agent"},
    )
    assert code == 200 and claim.get("claimed") is True, (code, claim)

    dec_patch = make_patch(
        "tier1-metacomplexity-dag",
        {
            "MetaComplexity/DecoderInjective.lean": """import MetaComplexity.Spec

namespace MetaComplexity

theorem encode_injective_of_lossless {n k : Nat} (c : LosslessCompressor n k) :
    Injective c.encode := by
  intro a b h
  have h1 := congrArg c.decode h
  rw [c.left_inv, c.left_inv] at h1
  exact h1

end MetaComplexity
"""
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier1-metacomplexity-dag/tasks/decoder_injective/submit",
        {"contributor": "euler-lean-agent", "patch": dec_patch},
    )
    assert code == 200 and res.get("accepted") is True, (code, res)
    print(f"  [PASS] Tier 1 decoder_injective ACCEPTED ({res['verify_ms']}ms)")

    pigeon_patch = make_patch(
        "tier1-metacomplexity-dag",
        {
            "MetaComplexity/Pigeonhole.lean": """import MetaComplexity.Spec

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
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier1-metacomplexity-dag/tasks/pigeonhole_fin/submit",
        {"contributor": "noether-lean-agent", "patch": pigeon_patch},
    )
    assert code == 200 and res.get("accepted") is True, (code, res)
    unlocked = set(res.get("unlocked_dependents", []))
    assert {"bijection_card_eq", "incompressibility_theorem", "non_surjective_decoder"}.issubset(
        unlocked
    ), unlocked
    print(f"  [PASS] Tier 1 pigeonhole_fin ACCEPTED & unlocked 3 downstream nodes ({res['verify_ms']}ms)")

    # 5b. Verify unlocked downstream node `bijection_card_eq`
    bij_patch = make_patch(
        "tier1-metacomplexity-dag",
        {
            "MetaComplexity/BijectionCard.lean": """import MetaComplexity.Spec
import MetaComplexity.Pigeonhole

namespace MetaComplexity

theorem bij_card_eq {n m : Nat}
    (f : Fin n → Fin m) (g : Fin m → Fin n)
    (hfg : ∀ x, g (f x) = x) (hgf : ∀ y, f (g y) = y) : n = m := by
  have hfinj : Injective f := fun a b h => by
    have := congrArg g h
    rw [hfg, hfg] at this
    exact this
  have hginj : Injective g := fun a b h => by
    have := congrArg f h
    rw [hgf, hgf] at this
    exact this
  by_cases h1 : m < n
  · exact False.elim (no_inj_lt h1 f hfinj)
  · by_cases h2 : n < m
    · exact False.elim (no_inj_lt h2 g hginj)
    · omega

end MetaComplexity
"""
        },
    )
    code, res = req(
        "POST",
        "/api/missions/tier1-metacomplexity-dag/tasks/bijection_card_eq/submit",
        {"contributor": "noether-lean-agent", "patch": bij_patch},
    )
    assert code == 200 and res.get("accepted") is True, (code, res)
    print(f"  [PASS] Tier 1 bijection_card_eq ACCEPTED ({res['verify_ms']}ms)")

    print("\nALL EXPANDED LAUNCH MISSION E2E CHECKS PASSED!")


if __name__ == "__main__":
    main()
