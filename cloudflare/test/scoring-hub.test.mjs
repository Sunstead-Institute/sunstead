import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";

// Exercise the real Hub logic/SQLite schema without a Cloudflare runtime or Lean.
const hooks = registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "cloudflare:workers") {
      return nextResolve("data:text/javascript,export class DurableObject{constructor(ctx){this.ctx=ctx}}", context);
    }
    if (specifier.startsWith(".") && !/\.[a-z]+$/.test(specifier)) {
      return nextResolve(specifier + ".ts", context);
    }
    return nextResolve(specifier, context);
  },
});
const { SunsteadHub } = await import("../src/hub_do.ts");
const { SEED_MISSIONS } = await import("../src/generated/missions.ts");
const { BUILD_PROVENANCE } = await import("../src/generated/provenance.ts");
const { SCORING_RULE_VERSION } = await import("../src/core.ts");
hooks.deregister();

const missionId = "sorting-networks-opt";
const taskId = "sort_n10";
const origin = "https://sunstead.test";
const mission = SEED_MISSIONS.find((s) => s.manifest.id === missionId);
const patch = `diff --git a/SortNet/Net10.lean b/SortNet/Net10.lean
--- a/SortNet/Net10.lean
+++ b/SortNet/Net10.lean
@@ -1 +1 @@
-old
+new
`;

function createHub(t) {
  const db = new DatabaseSync(":memory:");
  t.after(() => db.close());
  const pending = [];
  const hub = new SunsteadHub({
    blockConcurrencyWhile(init) { pending.push(init()); },
    storage: {
      sql: {
        exec(query, ...args) {
          let rows = [];
          if (/^\s*(SELECT|PRAGMA)\b/i.test(query)) rows = db.prepare(query).all(...args);
          else if (args.length > 0) db.prepare(query).run(...args);
          else db.exec(query);
          return { toArray: () => rows, one: () => {
            assert.equal(rows.length, 1, query);
            return rows[0];
          } };
        },
      },
    },
  }, {});
  return { db, hub, ready: Promise.all(pending) };
}

test("at commit time, a missing best_known cannot accept the sort_n10 tie or change its record", async (t) => {
  const { db, hub, ready } = createHub(t);
  await ready;
  const task = hub.getTasks(missionId).find((row) => row.def.id === taskId);
  assert.equal(task.best_score, 31);
  assert.equal(task.def.best_known.value, 29);
  const patchSha = "a".repeat(64);
  const subId = "sort-n10";
  db.prepare(
    "INSERT INTO submissions (id, mission_id, task_id, contributor, status, accepted, summary, patch_sha256, verify_ms, created_at) VALUES (?, ?, ?, 'solver', 'verifying', 0, '', ?, 0, 1)"
  ).run(subId, missionId, taskId, patchSha);
  const opts = { subId, mission, task, missionId, taskId, contributor: "solver", patch, patchSha, hubOrigin: origin };
  const verdict = { ok: true, score: 29, summary: "Verified", spec_sha256: mission.spec_sha256, verify_ms: 1, updated_files: { "changed.lean": "proof" } };
  hub.callVerifier = async () => {
    // Initial reads saw complete metadata; the simulated verifier round trip
    // leaves the persisted definition stale just before the final scoring read.
    const { best_known, ...withoutBestKnown } = task.def;
    db.prepare("UPDATE tasks SET def_json = ? WHERE mission_id = ? AND task_id = ?")
      .run(JSON.stringify(withoutBestKnown), missionId, taskId);
    return Response.json(verdict);
  };
  const failed = await hub.runVerificationJob(opts);
  assert.equal(failed.status, 503, JSON.stringify(failed.body));
  assert.equal(failed.body.status, "error");
  assert.match(failed.body.error, /no finite best_known/);
  const status = await hub.fetch(new Request(origin + "/api/submissions/" + subId));
  const statusBody = await status.json();
  assert.equal(statusBody.status, "error");
  assert.match(statusBody.error, /no finite best_known/);
  assert.equal(db.prepare("SELECT points FROM submissions WHERE id = ?").get(subId).points, 0);
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM accepted_patches").get().n, 0);
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM mission_files").get().n, 0);
  assert.equal(hub.getTasks(missionId).find((row) => row.def.id === taskId).best_score, 31);

  db.prepare("UPDATE tasks SET def_json = ? WHERE mission_id = ? AND task_id = ?")
    .run(JSON.stringify(task.def), missionId, taskId);
  hub.callVerifier = async () => Response.json(verdict);
  const accepted = await hub.runVerificationJob(opts);
  assert.equal(accepted.status, 200);
  assert.equal(accepted.body.points_awarded, 25);
  const proof = await hub.fetch(new Request(origin + "/api/proofs/" + accepted.body.proof_id));
  assert.equal(proof.status, 200);
  assert.deepEqual((await proof.json()).scoring, {
    ...BUILD_PROVENANCE,
    scoring_rule_version: SCORING_RULE_VERSION,
  });

  // Old ledger rows predate build attribution; don't label them with the current build.
  db.exec("UPDATE accepted_patches SET scoring_provenance_json = NULL");
  const old = await hub.fetch(new Request(origin + "/api/proofs/" + accepted.body.proof_id));
  assert.equal((await old.json()).scoring, null);
});

test("health reports the scoring build alongside its existing fields", async (t) => {
  const { hub, ready } = createHub(t);
  await ready;
  const resp = await hub.fetch(new Request(origin + "/api/health"));
  assert.equal(resp.status, 200);
  const { timestamp, ...body } = await resp.json();
  assert.ok(Number.isInteger(timestamp));
  assert.deepEqual(body, {
    ok: true,
    service: "sunstead-cloudflare",
    docker_verifier_ready: true,
    verifier_label: "Sandbox Ready · Cloudflare",
    verifier_backend: "cloudflare-containers",
    registered_contributors: 0,
    git_sha: BUILD_PROVENANCE.git_sha,
    mission_bundle_sha256: BUILD_PROVENANCE.mission_bundle_sha256,
    scoring_rule_version: SCORING_RULE_VERSION,
  });
});
