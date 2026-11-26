// Exercise the actual HTTP handlers with a stubbed Durable Object store and auth.
import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { test } from "node:test";

const hooks = registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "cloudflare:workers") {
      return nextResolve("data:text/javascript,export class DurableObject {}", context);
    }
    if (specifier === "./generated/missions") {
      return nextResolve("data:text/javascript,export const SEED_MISSIONS = []; export const getMissionSeedFiles = () => ({});", context);
    }
    if (specifier.startsWith("./") && !specifier.endsWith(".ts") && context.parentURL?.includes("/src/")) {
      return nextResolve(`${specifier}.ts`, context);
    }
    return nextResolve(specifier, context);
  },
});
const { SunsteadHub } = await import("../src/hub_do.ts");
hooks.deregister();

function fixture() {
  const id = "sorting";
  const open = { id: "size", title: "Size", target_files: [] };
  const closed = {
    id: "depth", title: "Depth", target_files: [],
    best_known: {
      value: 7,
      proven_optimal: { source: "No depth-six network exists", url: "https://example.org/proof" },
    },
  };
  const manifest = {
    id, title: "Sorting", tier: 2, mode: "hillclimb",
    verifier: { image: "sunstead/verifier-lean4:v0.2" }, frozen_paths: [],
    tasks: [open, closed],
  };
  const mission = { manifest, spec_sha256: "spec" };
  const tasks = manifest.tasks.map((def) => ({
    def, status: "open", best_score: null, active_lease: null,
  }));
  const hub = Object.assign(Object.create(SunsteadHub.prototype), {
    getMissionRow: (mid) => mid === id ? mission : null,
    getTasks: () => tasks,
    resolveContributor: async () => ({ ok: true, handle: "tester" }),
    withLock: async (_locks, _key, fn) => fn(),
  });
  const closedMission = {
    ...mission,
    manifest: { ...manifest, id: "all-closed", tasks: [closed] },
  };
  hub.listMissionsRows = () => [mission, closedMission];
  hub.getAllTasksByMission = () => new Map([[id, tasks], ["all-closed", [tasks[1]]]]);
  hub.ctx = { storage: { sql: { exec: () => ({ toArray: () => [] }) } } };
  return { hub };
}

const request = (path, body) => new Request(`https://hub.test/api/missions/sorting${path}`, body
  ? { method: "POST", body: JSON.stringify(body) }
  : undefined);

test("closed task claim and sync/async submission reject before rate limits or verifier work", async () => {
  const { hub } = fixture();
  hub.checkRateLimit = () => assert.fail("closed task must not consume quota");
  hub.getVerifier = () => assert.fail("closed task must not reach a verifier");
  for (const [route, body] of [
    ["claim", {}],
    ["submit", { patch: "draft", async: false }],
    ["submit?async=1", { patch: "draft" }],
  ]) {
    const response = await hub.fetch(request(`/tasks/depth/${route}`, body));
    assert.equal(response.status, 409);
    assert.match((await response.json()).error, /depth.*closed: 7 is proven optimal/);
  }
});

test("API summaries and details exclude closed tasks from frontier but preserve their definitions", async () => {
  const { hub } = fixture();
  hub.getRecentSubmissions = () => [];
  const summaries = await (await hub.fetch(new Request("https://hub.test/api/missions"))).json();
  const sorting = summaries.missions.find((m) => m.id === "sorting");
  assert.deepEqual(sorting.frontier_task_ids, ["size"]);
  assert.equal(sorting.proven_optimal_tasks, 1);
  assert.equal(sorting.verified_tasks, 0);
  const detail = await (await hub.fetch(request(""))).json();
  assert.deepEqual(detail.frontier, ["size"]);
  assert.equal(detail.tasks[1].status, "open");
  assert.equal(detail.tasks[1].def.best_known.proven_optimal.url, "https://example.org/proof");
});

test("global frontier and has_frontier mission filter exclude closed work", async () => {
  const { hub } = fixture();
  async function get(path) {
    const response = await hub.fetch(new Request(`https://hub.test/api/${path}`));
    assert.equal(response.status, 200);
    return response.json();
  }
  const frontier = await get("frontier");
  assert.equal(frontier.total_matching, 1);
  assert.deepEqual(frontier.tasks.map((t) => [t.mission_id, t.task_id]), [["sorting", "size"]]);
  const unfiltered = await get("missions");
  assert.deepEqual(unfiltered.missions.find((m) => m.id === "all-closed").frontier_task_ids, []);
  const filtered = await get("missions?has_frontier=true");
  assert.deepEqual(filtered.missions.map((m) => m.id), ["sorting"]);
});
