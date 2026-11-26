import assert from "node:assert/strict";
import test from "node:test";
import { handleMcp } from "../src/mcp.ts";

const task = { mission_id: "example", task_id: "task_1" };
const tools = [
  [
    "register_contributor",
    { handle: "ada-lover", display_name: "Ada", github: "ada-gh" },
    "/api/contributors/register",
    "",
    "POST",
    { handle: "ada-lover", display_name: "Ada", github: "ada-gh" },
  ],
  ["get_me", {}, "/api/me", "", "GET", undefined],
  ["list_missions", {}, "/api/missions", "", "GET", undefined],
  ["get_mission_frontier", { mission_id: "example" }, "/api/missions/example", "", "GET", undefined],
  ["get_task_files", task, "/api/missions/example/tasks/task_1/files", "", "GET", undefined],
  ["get_verified_proof", task, "/api/missions/example/tasks/task_1/proof", "", "GET", undefined],
  ["claim_task", { ...task, lease_seconds: 900 }, "/api/missions/example/tasks/task_1/claim", "", "POST", { lease_seconds: 900 }],
  ["release_task", task, "/api/missions/example/tasks/task_1/release", "", "POST", {}],
  ["submit_patch", { ...task, patch: "diff" }, "/api/missions/example/tasks/task_1/submit", "?async=1", "POST", { patch: "diff" }],
  ["get_submission_status", { submission_id: "sub-abc-123" }, "/api/submissions/sub-abc-123", "", "GET", undefined],
  [
    "update_profile",
    { display_name: "Ada", github: "ada-gh", x: null, linkedin: "ada-lovelace" },
    "/api/me",
    "",
    "PATCH",
    { display_name: "Ada", github: "ada-gh", x: null, linkedin: "ada-lovelace" },
  ],
  [
    "decompose_task",
    {
      ...task,
      decomp_id: "d1",
      subgoals: [
        { id: "lemma_a", title: "Lemma A", statement: "def lemma_a : Prop := 1 = 1" },
        { id: "lemma_b", title: "Lemma B", statement: "def lemma_b : Prop := 2 = 2" },
      ],
      reduction_file: "Pkg/Decomp_task_1_d1.lean",
      reduction_theorem: "Pkg.reduce_task_1",
      patch: "diff --git a/Pkg/Decomp_task_1_d1.lean b/Pkg/Decomp_task_1_d1.lean\n",
    },
    "/api/missions/example/tasks/task_1/decompose",
    "",
    "POST",
    {
      decomp_id: "d1",
      subgoals: [
        { id: "lemma_a", title: "Lemma A", statement: "def lemma_a : Prop := 1 = 1" },
        { id: "lemma_b", title: "Lemma B", statement: "def lemma_b : Prop := 2 = 2" },
      ],
      reduction_file: "Pkg/Decomp_task_1_d1.lean",
      reduction_theorem: "Pkg.reduce_task_1",
      patch: "diff --git a/Pkg/Decomp_task_1_d1.lean b/Pkg/Decomp_task_1_d1.lean\n",
    },
  ],
  [
    "refute_task",
    {
      ...task,
      refute_file: "Pkg/Refute_task_1.lean",
      refute_theorem: "Pkg.refute_task_1",
      patch: "diff --git a/Pkg/Refute_task_1.lean b/Pkg/Refute_task_1.lean\n",
    },
    "/api/missions/example/tasks/task_1/refute",
    "?async=1",
    "POST",
    {
      refute_file: "Pkg/Refute_task_1.lean",
      refute_theorem: "Pkg.refute_task_1",
      patch: "diff --git a/Pkg/Refute_task_1.lean b/Pkg/Refute_task_1.lean\n",
    },
  ],
] as const;

function rpc(method: string, params: object, extra: Record<string,string> = {}) {
  return new Request("https://sunstead.test/mcp", {
    method: "POST",
    headers: {Accept: "application/json, text/event-stream", "Content-Type": "application/json", ...extra},
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
}
const unexpected = async () => { throw new Error("unexpected hub call"); };

test("remote MCP initialization and tools/list", async () => {
  const init = await handleMcp(rpc("initialize", {
    protocolVersion: "2025-11-25", capabilities: {}, clientInfo: {name: "test", version: "1"},
  }), unexpected);
  assert.equal((await init.json()).result.serverInfo.name, "sunstead");
  const list = await handleMcp(rpc("tools/list", {}), unexpected);
  assert.deepEqual((await list.json()).result.tools.map(t => t.name).sort(), tools.map(([name]) => name).sort());
});

for (const [name, args, path, search, method, body] of tools) {
  test(name + " forwards to the existing hub handler", async () => {
    let calls = 0;
    const req = rpc("tools/call", {name, arguments: args}, {Authorization: "Bearer test", "CF-Connecting-IP": "192.0.2.1"});
    const result = await handleMcp(req, async forwarded => {
      calls++;
      const parsed = new URL(forwarded.url);
      assert.equal(parsed.pathname, path);
      assert.equal(parsed.search, search);
      assert.equal(forwarded.method, method);
      assert.equal(forwarded.headers.get("Authorization"), "Bearer test");
      assert.equal(forwarded.headers.get("CF-Connecting-IP"), "192.0.2.1");
      if (body) assert.deepEqual(await forwarded.json(), body);
      return Response.json({ok: true});
    });
    assert.equal(calls, 1);
    assert.equal((await result.json()).result.content[0].text, '{"ok":true}');
  });
}

test("submit_patch supports explicit async: false opt-in for synchronous verification", async () => {
  let seenSearch = "";
  const req = rpc("tools/call", { name: "submit_patch", arguments: { ...task, patch: "diff", async: false } });
  const res = await handleMcp(req, async (forwarded) => {
    seenSearch = new URL(forwarded.url).search;
    return Response.json({ accepted: true });
  });
  assert.equal(seenSearch, "");
  assert.equal((await res.json()).result.content[0].text, '{"accepted":true}');
});

test("refute_task supports explicit async: false opt-in for synchronous verification", async () => {
  let seenSearch = "";
  let seenBody: Record<string, unknown> = {};
  const req = rpc("tools/call", {
    name: "refute_task",
    arguments: {
      ...task,
      refute_file: "Pkg/Refute.lean",
      refute_theorem: "Pkg.refute",
      patch: "diff",
      async: false,
    },
  });
  const res = await handleMcp(req, async (forwarded) => {
    seenSearch = new URL(forwarded.url).search;
    seenBody = (await forwarded.json()) as Record<string, unknown>;
    return Response.json({ refuted: true });
  });
  assert.equal(seenSearch, "");
  assert.equal("async" in seenBody, false);
  assert.equal((await res.json()).result.content[0].text, '{"refuted":true}');
});

test("OPTIONS /mcp handles CORS preflight and rejects cross-origin preflights", async () => {
  const sameOrigin = new Request("https://sunstead.test/mcp", {
    method: "OPTIONS",
    headers: { Origin: "https://sunstead.test" },
  });
  const ok = await handleMcp(sameOrigin, unexpected);
  assert.equal(ok.status, 204);
  assert.equal(ok.headers.get("Access-Control-Allow-Origin"), "https://sunstead.test");
  assert.match(ok.headers.get("Access-Control-Allow-Methods") ?? "", /POST/);
  assert.match(ok.headers.get("Access-Control-Allow-Headers") ?? "", /Authorization/);

  const noOrigin = new Request("https://sunstead.test/mcp", { method: "OPTIONS" });
  assert.equal((await handleMcp(noOrigin, unexpected)).status, 204);

  const crossOrigin = new Request("https://sunstead.test/mcp", {
    method: "OPTIONS",
    headers: { Origin: "https://evil.example" },
  });
  assert.equal((await handleMcp(crossOrigin, unexpected)).status, 403);

  const badMethod = new Request("https://sunstead.test/mcp", { method: "GET" });
  const m405 = await handleMcp(badMethod, unexpected);
  assert.equal(m405.status, 405);
  assert.equal(m405.headers.get("Allow"), "POST, OPTIONS");
});

test("hub denials reach the client and invalid origins never reach the hub", async () => {
  const req = rpc("tools/call", {name: "release_task", arguments: task});
  const denied = await handleMcp(req, async forwarded => {
    assert.equal(forwarded.headers.get("Authorization"), null);
    return Response.json({error: "authentication required"}, {status: 401});
  });
  const result = (await denied.json()).result;
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /401.*authentication required/);
  const crossOrigin = rpc("tools/list", {}, { Origin: "https://other.example" });
  assert.equal((await handleMcp(crossOrigin, unexpected)).status, 403);
});
