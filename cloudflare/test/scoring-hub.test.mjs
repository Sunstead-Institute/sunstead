import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import historicalReplay from "../corrections/hillclimb-scoring-2026-11-26-01.json" with { type: "json" };
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
const { applyPointCorrections } = await import("../src/point_corrections.ts");
hooks.deregister();
const { handleMcp } = await import("../src/mcp.ts");

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
  const storage = {
    transactionSync(fn) {
      db.exec("BEGIN");
      try {
        const result = fn();
        db.exec("COMMIT");
        return result;
      } catch (err) {
        db.exec("ROLLBACK");
        throw err;
      }
    },
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
  };
  function restart() {
    const pending = [];
    const hub = new SunsteadHub({
      blockConcurrencyWhile(init) { pending.push(init()); },
      storage,
    }, {});
    return { hub, ready: Promise.all(pending) };
  }
  return { db, storage, restart, ...restart() };
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
    point_corrections: [{
      batch_id: historicalReplay.batch_id,
      status: "error",
      error: `submission not found: ${historicalReplay.entries[0].submission_id}`,
    }],
  });
});

const testToken = "local-test-only";
const testTokenHash = "sha256:" + createHash("sha256").update(testToken).digest("hex");
const sample = historicalReplay.entries.find((e) => e.submission_id === "723828fd-2d9c-4554-89a4-6afe85367520");
const sampleHash = createHash("sha256").update(patch).digest("hex");
const samplePath = `/api/submissions/${sample.submission_id}`;

function loadHistory(db) {
  const insert = db.prepare(`
    INSERT INTO submissions
      (id, mission_id, task_id, contributor, status, accepted, summary, points, patch_sha256, verify_ms, created_at)
    VALUES (?, ?, ?, ?, 'accepted', 1, 'historical award', ?, ?, 0, 1)
  `);
  for (const e of historicalReplay.entries) {
    insert.run(e.submission_id, missionId, taskId, e.contributor, e.original_points, "sha256:" + sampleHash);
  }
  insert.run("uncorrected", missionId, taskId, "other", 800, "sha256:" + "0".repeat(64));
  db.prepare(`
    INSERT INTO accepted_patches
      (mission_id, task_id, submission_id, contributor, summary, patch, patch_sha256, spec_sha256, created_at)
    VALUES (?, ?, ?, ?, 'Verified (+333 pts)', ?, ?, ?, 1)
  `).run(missionId, taskId, sample.submission_id, sample.contributor, patch, "sha256:" + sampleHash, mission.spec_sha256);
  db.prepare(`
    INSERT INTO contributors (handle, display_name, token_sha256, created_at) VALUES (?, ?, ?, 1)
  `).run(sample.contributor, "Test contributor", testTokenHash);
  // One live crown for the unaffected submitter; no correction should alter it.
  db.prepare(`
    UPDATE tasks SET best_score = 28, verified_by = 'other', status = 'verified'
     WHERE mission_id = ? AND task_id = ?
  `).run(missionId, taskId);
}

async function get(hub, path, authenticated = false) {
  const response = await hub.fetch(new Request(origin + path, {
    headers: authenticated ? { Authorization: `Bearer ${testToken}` } : {},
  }));
  assert.equal(response.status, 200, path);
  return response.json();
}

async function mcp(hub, name, args) {
  const response = await handleMcp(new Request(origin + "/mcp", {
    method: "POST",
    headers: {
      Accept: "application/json, text/event-stream",
      "Content-Type": "application/json",
      Authorization: `Bearer ${testToken}`,
    },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: args } }),
  }), (req) => hub.fetch(req));
  assert.equal(response.status, 200);
  const { result } = await response.json();
  assert.ok(!result.isError, JSON.stringify(result));
  return JSON.parse(result.content[0].text);
}

async function board(hub) {
  return (await get(hub, "/api/leaderboard")).leaderboard.map((e) => [e.contributor, e.points, e.active_records]);
}

function awardFields(row) {
  return [row.original_points, row.points_delta, row.effective_points];
}

test("committed replay applies at startup, preserves awards, and reranks the leaderboard and profiles", async (t) => {
  const { db, hub, ready, restart, storage } = createHub(t);
  await ready;
  loadHistory(db);
  const before = await board(hub);
  assert.deepEqual(before, [["codex-dirichlet", 19558, 0], ["theorem-tom", 18076, 0], ["other", 950, 1]]);
  const updated = restart();
  await updated.ready;

  assert.deepEqual((await get(updated.hub, "/api/health")).point_corrections,
    [{ batch_id: historicalReplay.batch_id, status: "applied" }]);
  const applied = (await get(updated.hub, "/api/corrections")).batches;
  assert.equal(applied.length, 1);
  const { applied_at, entries, ...metadata } = applied[0];
  const { entries: expected, ...expectedMetadata } = historicalReplay;
  assert.ok(Number.isSafeInteger(applied_at));
  assert.deepEqual(metadata, expectedMetadata);
  assert.deepEqual(entries, [...expected].sort((a, b) => a.submission_id.localeCompare(b.submission_id)));
  const after = [["other", 950, 1], ["theorem-tom", 565, 0], ["codex-dirichlet", 100, 0]];
  assert.deepEqual(await board(updated.hub), after);

  const row = await get(updated.hub, samplePath);
  assert.deepEqual(awardFields(row), [333, -308, 25]);
  assert.equal(row.points_awarded, 333);
  const list = (await get(updated.hub, "/api/submissions?limit=200")).submissions;
  for (const entry of expected) {
    const row = list.find((r) => r.id === entry.submission_id);
    assert.deepEqual(awardFields(row), [entry.original_points, entry.delta, entry.replayed_points]);
    assert.equal(row.points, entry.original_points);
  }
  const page = await get(updated.hub, "/api/contributors/theorem-tom");
  assert.equal(page.rank, 2);
  assert.equal(page.stats.points, 565);
  assert.deepEqual(awardFields(page.recent_submissions.find((r) => r.id === sample.submission_id)), [333, -308, 25]);
  assert.equal((await get(updated.hub, "/api/me", true)).points, 565);
  assert.equal((await mcp(updated.hub, "get_me", {})).points, 565);
  assert.deepEqual(awardFields(await mcp(updated.hub, "get_submission_status", { submission_id: sample.submission_id })), [333, -308, 25]);
  assert.deepEqual(awardFields(await mcp(updated.hub, "get_verified_proof", { mission_id: missionId, task_id: taskId })), [333, -308, 25]);
  const [proof] = (await get(updated.hub, "/api/proofs")).proofs;
  assert.deepEqual(awardFields(proof), [333, -308, 25]);
  const permalink = await get(updated.hub, "/api/proofs/" + sampleHash);
  assert.deepEqual(awardFields(permalink), [333, -308, 25]);
  assert.equal(permalink.summary, "Verified (+333 pts)");

  assert.equal(db.prepare("SELECT points FROM submissions WHERE id = ?").get(sample.submission_id).points, 333);
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM accepted_patches").get().n, 1);

  assert.deepEqual(applyPointCorrections(storage, [historicalReplay]), [{ batch_id: historicalReplay.batch_id, status: "applied" }]);
  const next = restart();
  await next.ready;
  assert.deepEqual((await get(next.hub, "/api/corrections")).batches, applied);
  assert.deepEqual(await board(next.hub), after);

  const altered = structuredClone(historicalReplay);
  altered.entries[0].reason = "amended in place";
  assert.match(applyPointCorrections(storage, [altered])[0].error, /already applied with different contents/);
  assert.deepEqual((await get(next.hub, "/api/corrections")).batches, applied);
});

test("each submission mismatch rejects the whole committed batch and is visible in health", async (t) => {
  for (const [label, bad] of [
    ["not found", "DELETE FROM submissions WHERE id = ?"],
    ["not accepted", "UPDATE submissions SET accepted = 0, status = 'rejected' WHERE id = ?"],
    ["contributor mismatch", "UPDATE submissions SET contributor = 'other' WHERE id = ?"],
    ["original points mismatch", "UPDATE submissions SET points = points + 1 WHERE id = ?"],
  ]) {
    await t.test(label, async (t) => {
      const { db, hub, ready, restart } = createHub(t);
      await ready;
      loadHistory(db);
      const last = historicalReplay.entries.at(-1).submission_id;
      db.prepare(bad).run(last);
      const before = await board(hub);
      const next = restart();
      await next.ready;

      const [status] = (await get(next.hub, "/api/health")).point_corrections;
      assert.equal(status.status, "error");
      assert.match(status.error, new RegExp(label));
      assert.ok(status.error.endsWith(last));
      assert.equal(db.prepare("SELECT COUNT(*) AS n FROM point_corrections").get().n, 0);
      assert.deepEqual(await get(next.hub, "/api/corrections"), { batches: [] });
      assert.deepEqual(await board(next.hub), before);
    });
  }
});

test("a storage failure after the first entry rolls back the complete batch", async (t) => {
  const { db, ready, restart } = createHub(t);
  await ready;
  loadHistory(db);
  db.exec(`CREATE TRIGGER fail_write BEFORE INSERT ON point_corrections
    WHEN (SELECT COUNT(*) FROM point_corrections) = 1
    BEGIN SELECT RAISE(ABORT, 'test write failure'); END`);
  const next = restart();
  await next.ready;
  const [status] = (await get(next.hub, "/api/health")).point_corrections;
  assert.equal(status.status, "error");
  assert.match(status.error, /test write failure/);
  assert.deepEqual(await get(next.hub, "/api/corrections"), { batches: [] });
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM point_corrections").get().n, 0);
});

test("a linked compensation restores the original totals while retaining both batches", async (t) => {
  const { db, hub, ready, restart, storage } = createHub(t);
  await ready;
  loadHistory(db);
  const before = await board(hub);
  const next = restart();
  await next.ready;
  const reversal = {
    ...historicalReplay,
    batch_id: "test-compensation",
    reverses_batch_id: historicalReplay.batch_id,
    entries: historicalReplay.entries.map((e) => ({
      ...e, replayed_points: e.original_points, delta: -e.delta || 0, reason: "Reverse the historical replay.",
    })),
  };
  assert.match(applyPointCorrections(storage, [{ ...reversal, entries: reversal.entries.slice(1) }])[0].error,
    /must cover the original batch/);
  assert.deepEqual(applyPointCorrections(storage, [reversal, reversal]),
    [{ batch_id: reversal.batch_id, status: "applied" }, { batch_id: reversal.batch_id, status: "applied" }]);
  assert.match(applyPointCorrections(storage, [{ ...reversal, batch_id: "second-attempt" }])[0].error,
    /already has a compensation/);
  assert.deepEqual(await board(next.hub), before);
  const { batches } = await get(next.hub, "/api/corrections");
  assert.equal(batches.length, 2);
  assert.equal(batches.find((b) => b.batch_id === reversal.batch_id).reverses_batch_id, historicalReplay.batch_id);
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM point_corrections").get().n, 64);
  assert.deepEqual(awardFields(await get(next.hub, samplePath)), [333, 0, 333]);
});
