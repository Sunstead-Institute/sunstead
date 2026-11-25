import assert from "node:assert/strict";
import test from "node:test";
import { handleMcp } from "../src/mcp.ts";

const task = { mission_id: "example", task_id: "task_1" };
const tools = [
  ["list_missions", {}, "/api/missions", undefined],
  ["get_mission_frontier", {mission_id: "example"}, "/api/missions/example", undefined],
  ["get_task_files", task, "/api/missions/example/tasks/task_1/files", undefined],
  ["get_verified_proof", task, "/api/missions/example/tasks/task_1/proof", undefined],
  ["claim_task", {...task, lease_seconds: 900}, "/api/missions/example/tasks/task_1/claim", {lease_seconds: 900}],
  ["release_task", task, "/api/missions/example/tasks/task_1/release", {}],
  ["submit_patch", {...task, patch: "diff"}, "/api/missions/example/tasks/task_1/submit", {patch: "diff"}],
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

for (const [name, args, path, body] of tools) {
  test(name + " forwards to the existing hub handler", async () => {
    let calls = 0;
    const req = rpc("tools/call", {name, arguments: args}, {Authorization: "Bearer test", "CF-Connecting-IP": "192.0.2.1"});
    const result = await handleMcp(req, async forwarded => {
      calls++;
      assert.equal(new URL(forwarded.url).pathname, path);
      assert.equal(forwarded.method, body ? "POST" : "GET");
      assert.equal(forwarded.headers.get("Authorization"), "Bearer test");
      assert.equal(forwarded.headers.get("CF-Connecting-IP"), "192.0.2.1");
      if (body) assert.deepEqual(await forwarded.json(), body);
      return Response.json({ok: true});
    });
    assert.equal(calls, 1);
    assert.equal((await result.json()).result.content[0].text, '{"ok":true}');
  });
}

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
