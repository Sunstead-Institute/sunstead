import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import * as nodeModule from "node:module";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { BASE_SECURITY_HEADERS, HTML_CONTENT_SECURITY_POLICY } from "../src/core.ts";
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
  ["get_open_frontier", {}, "/api/frontier", "", "GET", undefined],
  ["get_mission_frontier", { mission_id: "example" }, "/api/missions/example", "", "GET", undefined],
  ["get_task_files", task, "/api/missions/example/tasks/task_1/files", "", "GET", undefined],
  ["get_verified_proof", task, "/api/missions/example/tasks/task_1/proof", "", "GET", undefined],
  ["claim_task", { ...task, lease_seconds: 900 }, "/api/missions/example/tasks/task_1/claim", "", "POST", { lease_seconds: 900 }],
  ["release_task", task, "/api/missions/example/tasks/task_1/release", "", "POST", {}],
  ["submit_patch", { ...task, patch: "diff" }, "/api/missions/example/tasks/task_1/submit", "?async=1", "POST", { patch: "diff" }],
  ["list_submissions", {}, "/api/submissions", "", "GET", undefined],
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
  assert.equal(ok.headers.get("Cache-Control"), "no-store");

  const noOrigin = new Request("https://sunstead.test/mcp", { method: "OPTIONS" });
  const okNoOrigin = await handleMcp(noOrigin, unexpected);
  assert.equal(okNoOrigin.status, 204);
  assert.equal(okNoOrigin.headers.get("Cache-Control"), "no-store");

  const crossOrigin = new Request("https://sunstead.test/mcp", {
    method: "OPTIONS",
    headers: { Origin: "https://evil.example" },
  });
  const forbidden = await handleMcp(crossOrigin, unexpected);
  assert.equal(forbidden.status, 403);
  assert.equal(forbidden.headers.get("Cache-Control"), "no-store");

  const badMethod = new Request("https://sunstead.test/mcp", { method: "GET" });
  const m405 = await handleMcp(badMethod, unexpected);
  assert.equal(m405.status, 405);
  assert.equal(m405.headers.get("Allow"), "POST, OPTIONS");
  assert.equal(m405.headers.get("Cache-Control"), "no-store");
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

test("get_open_frontier forwards all filter and pagination query parameters to GET /api/frontier", async () => {
  let seenUrl: URL | null = null;
  let seenMethod = "";
  const req = rpc("tools/call", {
    name: "get_open_frontier",
    arguments: {
      unclaimed: true,
      mode: "dag",
      tier: 1,
      open_conjecture: true,
      toolchain: "v4.36.0",
      mission: "fc-erdos-open",
      q: "prime",
      limit: 25,
      offset: 5,
    },
  });
  const res = await handleMcp(req, async (forwarded) => {
    seenUrl = new URL(forwarded.url);
    seenMethod = forwarded.method;
    return Response.json({ total_matching: 1, limit: 25, offset: 5, returned: 1, tasks: [] });
  });
  assert.equal(seenMethod, "GET");
  assert.equal(seenUrl!.pathname, "/api/frontier");
  assert.equal(seenUrl!.searchParams.get("unclaimed"), "true");
  assert.equal(seenUrl!.searchParams.get("mode"), "dag");
  assert.equal(seenUrl!.searchParams.get("tier"), "1");
  assert.equal(seenUrl!.searchParams.get("open_conjecture"), "true");
  assert.equal(seenUrl!.searchParams.get("toolchain"), "v4.36.0");
  assert.equal(seenUrl!.searchParams.get("mission"), "fc-erdos-open");
  assert.equal(seenUrl!.searchParams.get("q"), "prime");
  assert.equal(seenUrl!.searchParams.get("limit"), "25");
  assert.equal(seenUrl!.searchParams.get("offset"), "5");
  assert.equal((await res.json()).result.isError, false);
});

test("list_missions forwards optional filter query parameters to GET /api/missions", async () => {
  let seenUrl: URL | null = null;
  const req = rpc("tools/call", {
    name: "list_missions",
    arguments: {
      mode: "hillclimb",
      tier: 2,
      open_conjecture: false,
      toolchain: "v4.31.0",
      has_frontier: true,
      q: "rank",
    },
  });
  const res = await handleMcp(req, async (forwarded) => {
    seenUrl = new URL(forwarded.url);
    return Response.json({ missions: [] });
  });
  assert.equal(seenUrl!.pathname, "/api/missions");
  assert.equal(seenUrl!.searchParams.get("mode"), "hillclimb");
  assert.equal(seenUrl!.searchParams.get("tier"), "2");
  assert.equal(seenUrl!.searchParams.get("open_conjecture"), "false");
  assert.equal(seenUrl!.searchParams.get("toolchain"), "v4.31.0");
  assert.equal(seenUrl!.searchParams.get("has_frontier"), "true");
  assert.equal(seenUrl!.searchParams.get("q"), "rank");
  assert.equal((await res.json()).result.isError, false);
});

test("get_open_frontier and list_missions validate Zod parameter bounds before calling hub", async () => {
  const badLimit = await handleMcp(
    rpc("tools/call", { name: "get_open_frontier", arguments: { limit: 500 } }),
    unexpected
  );
  assert.equal((await badLimit.json()).result.isError, true);

  const badMission = await handleMcp(
    rpc("tools/call", { name: "get_open_frontier", arguments: { mission: "../escape" } }),
    unexpected
  );
  assert.equal((await badMission.json()).result.isError, true);

  const badMode = await handleMcp(
    rpc("tools/call", { name: "list_missions", arguments: { mode: "unknown" } }),
    unexpected
  );
  assert.equal((await badMode.json()).result.isError, true);
});

test("list_submissions forwards all optional filter parameters to GET /api/submissions", async () => {
  let seenUrl: URL | null = null;
  let seenMethod = "";
  const req = rpc("tools/call", {
    name: "list_submissions",
    arguments: {
      mission: "fc-erdos-open",
      task: "erdos_1",
      contributor: "Ada.Lovelace_1",
      status: "accepted",
      limit: 50,
    },
  });
  const res = await handleMcp(req, async (forwarded) => {
    seenUrl = new URL(forwarded.url);
    seenMethod = forwarded.method;
    return Response.json({ submissions: [] });
  });
  assert.equal(seenMethod, "GET");
  assert.equal(seenUrl!.pathname, "/api/submissions");
  assert.equal(seenUrl!.searchParams.get("mission"), "fc-erdos-open");
  assert.equal(seenUrl!.searchParams.get("task"), "erdos_1");
  assert.equal(seenUrl!.searchParams.get("contributor"), "Ada.Lovelace_1");
  assert.equal(seenUrl!.searchParams.get("status"), "accepted");
  assert.equal(seenUrl!.searchParams.get("limit"), "50");
  assert.equal((await res.json()).result.isError, false);
});

test("MCP tools enforce Zod string bounds and contributor/status validation before calling hub", async () => {
  const invalidCalls: Array<[string, Record<string, unknown>]> = [
    ["list_submissions", { limit: 201 }],
    ["list_submissions", { limit: 0 }],
    ["list_submissions", { status: "pending" }],
    ["list_submissions", { contributor: "../escape" }],
    ["list_submissions", { contributor: "a".repeat(37) }],
    ["list_submissions", { mission: "../escape" }],
    ["register_contributor", { handle: "" }],
    ["register_contributor", { handle: "a".repeat(65) }],
    ["register_contributor", { handle: "alice", display_name: "x".repeat(129) }],
    ["register_contributor", { handle: "alice", github: "g".repeat(65) }],
    ["register_contributor", { handle: "alice", x: "x".repeat(33) }],
    ["register_contributor", { handle: "alice", linkedin: "l".repeat(129) }],
    ["list_missions", { toolchain: "t".repeat(129) }],
    ["list_missions", { q: "q".repeat(201) }],
    ["submit_patch", { ...task, patch: "p".repeat(512 * 1024 + 1) }],
    [
      "decompose_task",
      {
        ...task,
        subgoals: [
          { id: "lemma_a", title: "T".repeat(201), statement: "def a : Prop := True" },
          { id: "lemma_b", title: "Lemma B", statement: "def b : Prop := True" },
        ],
        reduction_file: "Pkg/Red.lean",
        reduction_theorem: "Pkg.red",
        patch: "diff",
      },
    ],
    [
      "decompose_task",
      {
        ...task,
        subgoals: [
          { id: "lemma_a", title: "Lemma A", statement: "s".repeat(4097) },
          { id: "lemma_b", title: "Lemma B", statement: "def b : Prop := True" },
        ],
        reduction_file: "Pkg/Red.lean",
        reduction_theorem: "Pkg.red",
        patch: "diff",
      },
    ],
    [
      "refute_task",
      {
        ...task,
        refute_file: "Pkg/" + "a".repeat(260) + ".lean",
        refute_theorem: "Pkg.refute",
        patch: "diff",
      },
    ],
    [
      "refute_task",
      {
        ...task,
        refute_theorem: "a".repeat(257),
        patch: "diff",
      },
    ],
  ];

  for (const [name, args] of invalidCalls) {
    const res = await handleMcp(rpc("tools/call", { name, arguments: args }), unexpected);
    const body = (await res.json()) as { result?: { isError?: boolean }; error?: unknown };
    assert.equal(
      Boolean(body.result?.isError || body.error),
      true,
      `expected Zod validation error for ${name}(${JSON.stringify(Object.keys(args))})`
    );
  }
});

test("MCP forward() catches hub fetch exceptions cleanly without crashing transport", async () => {
  const res = await handleMcp(rpc("tools/call", { name: "list_submissions", arguments: {} }), async () => {
    throw new Error("Durable Object temporarily unavailable");
  });
  assert.equal(res.status, 200);
  const body = (await res.json()) as {
    result: { isError: boolean; content: Array<{ type: string; text: string }> };
  };
  assert.equal(body.result.isError, true);
  assert.match(body.result.content[0].text, /Hub request failed: Durable Object temporarily unavailable/);
});

// ---------------------------------------------------------------- Worker index.ts edge fetch tests

const FALLBACK_STATIC = {
  "/": { contentType: "text/html; charset=utf-8", body: "<!doctype html><title>Sunstead</title>" },
  "/styles.css": { contentType: "text/css; charset=utf-8", body: "body { color: #000; }" },
  "/proofs.html": { contentType: "text/html; charset=utf-8", body: "<!doctype html><title>Proofs</title>" },
};

const indexLoaderSource = `
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
const FALLBACK_STATIC = ${JSON.stringify(FALLBACK_STATIC)};
export async function resolve(specifier, context, nextResolve) {
  if (context.parentURL && context.parentURL.endsWith("/src/index.ts")) {
    if (specifier === "./hub_do") return { shortCircuit: true, url: "sunstead-test:///hub_do" };
    if (specifier === "./containers") return { shortCircuit: true, url: "sunstead-test:///containers" };
    if (specifier === "./mcp") return nextResolve("./mcp.ts", context);
    if (specifier === "./core") return nextResolve("./core.ts", context);
    if (specifier === "./generated/static") {
      const staticUrl = new URL("./generated/static.ts", context.parentURL);
      if (existsSync(fileURLToPath(staticUrl))) return nextResolve("./generated/static.ts", context);
      return { shortCircuit: true, url: "sunstead-test:///static" };
    }
  }
  return nextResolve(specifier, context);
}
export async function load(url, context, nextLoad) {
  if (url === "sunstead-test:///hub_do") return { format: "module", shortCircuit: true, source: "export class SunsteadHub {}" };
  if (url === "sunstead-test:///containers") return { format: "module", shortCircuit: true, source: "export class Lean4Verifier {} export class Lean4V435Verifier {} export class Lean4V431Verifier {}" };
  if (url === "sunstead-test:///static") return { format: "module", shortCircuit: true, source: "export const STATIC_ASSETS = " + JSON.stringify(FALLBACK_STATIC) + ";" };
  return nextLoad(url, context);
}
`;

let cachedWorker: { fetch: (req: Request, env: unknown) => Promise<Response> } | null = null;
async function getEdgeWorker() {
  if (!cachedWorker) {
    if (typeof nodeModule.registerHooks === "function") {
      nodeModule.registerHooks({
        resolve(specifier, context, nextResolve) {
          if (context.parentURL && context.parentURL.endsWith("/src/index.ts")) {
            if (specifier === "./hub_do") return { shortCircuit: true, url: "sunstead-test:///hub_do" };
            if (specifier === "./containers") return { shortCircuit: true, url: "sunstead-test:///containers" };
            if (specifier === "./mcp") return nextResolve("./mcp.ts", context);
            if (specifier === "./core") return nextResolve("./core.ts", context);
            if (specifier === "./generated/static") {
              const staticUrl = new URL("./generated/static.ts", context.parentURL);
              if (existsSync(fileURLToPath(staticUrl))) {
                return nextResolve("./generated/static.ts", context);
              }
              return { shortCircuit: true, url: "sunstead-test:///static" };
            }
          }
          return nextResolve(specifier, context);
        },
        load(url, context, nextLoad) {
          if (url === "sunstead-test:///hub_do") {
            return { format: "module", shortCircuit: true, source: "export class SunsteadHub {}" };
          }
          if (url === "sunstead-test:///containers") {
            return {
              format: "module",
              shortCircuit: true,
              source:
                "export class Lean4Verifier {} export class Lean4V435Verifier {} export class Lean4V431Verifier {}",
            };
          }
          if (url === "sunstead-test:///static") {
            return {
              format: "module",
              shortCircuit: true,
              source: `export const STATIC_ASSETS = ${JSON.stringify(FALLBACK_STATIC)};`,
            };
          }
          return nextLoad(url, context);
        },
      });
    } else {
      nodeModule.register(`data:text/javascript,${encodeURIComponent(indexLoaderSource)}`);
    }
    const mod = await import("../src/index.ts");
    cachedWorker = mod.default;
  }
  return cachedWorker!;
}

function makeMockEnv(hubFetch: (req: Request) => Promise<Response>) {
  return {
    HUB: {
      getByName(name: string) {
        assert.equal(name, "sunstead-global-v1");
        return { fetch: hubFetch };
      },
    },
  };
}

function assertBaseSecurityHeaders(headers: Headers) {
  for (const [k, v] of Object.entries(BASE_SECURITY_HEADERS)) {
    assert.equal(headers.get(k), v, `missing or mismatched security header ${k}`);
  }
}

test("Worker index.ts redirects www.sunstead.org with 301 and security headers", async () => {
  const worker = await getEdgeWorker();
  const res = await worker.fetch(
    new Request("https://www.sunstead.org/proofs?mission=pnt#top"),
    makeMockEnv(unexpected)
  );
  assert.equal(res.status, 301);
  assert.equal(res.headers.get("Location"), "https://sunstead.org/proofs?mission=pnt");
  assertBaseSecurityHeaders(res.headers);
  assert.equal(res.headers.get("Content-Security-Policy"), null);
});

test("Worker index.ts serves static assets with deterministic weak ETag, 304 If-None-Match, and exact Cache-Control", async () => {
  const worker = await getEdgeWorker();
  const env = makeMockEnv(unexpected);

  const htmlRes = await worker.fetch(new Request("https://sunstead.org/"), env);
  assert.equal(htmlRes.status, 200);
  assert.equal(htmlRes.headers.get("Content-Type"), "text/html; charset=utf-8");
  assert.equal(htmlRes.headers.get("Cache-Control"), "public, max-age=60");
  assertBaseSecurityHeaders(htmlRes.headers);
  assert.equal(htmlRes.headers.get("Content-Security-Policy"), HTML_CONTENT_SECURITY_POLICY);

  const etag = htmlRes.headers.get("ETag");
  assert.ok(etag, "expected ETag header on static asset");
  assert.match(etag, /^W\/"[0-9a-f]{8}-\d+"$/);
  const bodyBytes = new TextEncoder().encode(await htmlRes.text()).byteLength;
  assert.ok(etag.endsWith(`-${bodyBytes}"`), `expected ETag byte length ${bodyBytes}, got ${etag}`);

  // Exact match -> 304 Not Modified with empty body, ETag, Cache-Control, and CSP/security headers
  const res304 = await worker.fetch(
    new Request("https://sunstead.org/", { headers: { "If-None-Match": etag } }),
    env
  );
  assert.equal(res304.status, 304);
  assert.equal(await res304.text(), "");
  assert.equal(res304.headers.get("ETag"), etag);
  assert.equal(res304.headers.get("Cache-Control"), "public, max-age=60");
  assertBaseSecurityHeaders(res304.headers);
  assert.equal(res304.headers.get("Content-Security-Policy"), HTML_CONTENT_SECURITY_POLICY);

  // Comma-separated list match and wildcard * match -> 304
  const list304 = await worker.fetch(
    new Request("https://sunstead.org/", {
      headers: { "If-None-Match": `"stale-1", ${etag}, "stale-2"` },
    }),
    env
  );
  assert.equal(list304.status, 304);

  const star304 = await worker.fetch(
    new Request("https://sunstead.org/", { headers: { "If-None-Match": "*" } }),
    env
  );
  assert.equal(star304.status, 304);

  // Mismatched weak ETag -> 200 with full body
  const mismatch200 = await worker.fetch(
    new Request("https://sunstead.org/", { headers: { "If-None-Match": 'W/"00000000-0"' } }),
    env
  );
  assert.equal(mismatch200.status, 200);
  assert.equal(mismatch200.headers.get("ETag"), etag);
  assert.ok((await mismatch200.text()).length > 0);

  // Non-HTML static asset preserves public, max-age=300 and omits HTML CSP
  const cssRes = await worker.fetch(new Request("https://sunstead.org/styles.css"), env);
  assert.equal(cssRes.status, 200);
  assert.equal(cssRes.headers.get("Content-Type"), "text/css; charset=utf-8");
  assert.equal(cssRes.headers.get("Cache-Control"), "public, max-age=300");
  assert.match(cssRes.headers.get("ETag") ?? "", /^W\/"[0-9a-f]{8}-\d+"$/);
  assertBaseSecurityHeaders(cssRes.headers);
  assert.equal(cssRes.headers.get("Content-Security-Policy"), null);

  // HEAD request returns 200 with empty body and matching ETag
  const headRes = await worker.fetch(new Request("https://sunstead.org/", { method: "HEAD" }), env);
  assert.equal(headRes.status, 200);
  assert.equal(headRes.headers.get("ETag"), etag);
  assert.equal(await headRes.text(), "");
});

test("Worker index.ts serves /proofs/<sha> with ETag, CSP, 304, and returns 405 for non-GET/HEAD on static and ledger routes", async () => {
  const worker = await getEdgeWorker();
  const env = makeMockEnv(unexpected);
  const ledgerPath = `/proofs/${"a".repeat(64)}`;

  const res = await worker.fetch(new Request(`https://sunstead.org${ledgerPath}`), env);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("Content-Type"), "text/html; charset=utf-8");
  assert.equal(res.headers.get("Cache-Control"), "public, max-age=60");
  assertBaseSecurityHeaders(res.headers);
  assert.equal(res.headers.get("Content-Security-Policy"), HTML_CONTENT_SECURITY_POLICY);
  const etag = res.headers.get("ETag");
  assert.match(etag ?? "", /^W\/"[0-9a-f]{8}-\d+"$/);

  const notMod = await worker.fetch(
    new Request(`https://sunstead.org${ledgerPath}`, { headers: { "If-None-Match": etag! } }),
    env
  );
  assert.equal(notMod.status, 304);
  assert.equal(notMod.headers.get("ETag"), etag);
  assert.equal(notMod.headers.get("Content-Security-Policy"), HTML_CONTENT_SECURITY_POLICY);

  // Non-GET/HEAD on / and /proofs/<sha> and /styles.css -> 405 Method Not Allowed with Allow: GET, HEAD
  for (const [method, path] of [
    ["POST", "/"],
    ["DELETE", "/styles.css"],
    ["POST", ledgerPath],
    ["PUT", "/proofs"],
  ] as const) {
    const m405 = await worker.fetch(new Request(`https://sunstead.org${path}`, { method }), env);
    assert.equal(m405.status, 405, `expected 405 for ${method} ${path}`);
    assert.equal(m405.headers.get("Allow"), "GET, HEAD");
    assertBaseSecurityHeaders(m405.headers);
  }

  // Unknown path still returns 404 with security headers
  const m404 = await worker.fetch(new Request("https://sunstead.org/does-not-exist", { method: "POST" }), env);
  assert.equal(m404.status, 404);
  assertBaseSecurityHeaders(m404.headers);
});

test("Worker index.ts applies BASE_SECURITY_HEADERS and Cache-Control: no-store to all /mcp responses", async () => {
  const worker = await getEdgeWorker();
  const env = makeMockEnv(async () => Response.json({ submissions: [] }));

  // POST /mcp JSON-RPC tool call
  const postRes = await worker.fetch(
    new Request("https://sunstead.org/mcp", {
      method: "POST",
      headers: { Accept: "application/json, text/event-stream", "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: { name: "list_submissions", arguments: { status: "accepted", limit: 5 } },
      }),
    }),
    env
  );
  assert.equal(postRes.status, 200);
  assert.match(postRes.headers.get("Content-Type") ?? "", /application\/json/);
  assert.equal(postRes.headers.get("Cache-Control"), "no-store");
  assertBaseSecurityHeaders(postRes.headers);
  const rpcBody = (await postRes.json()) as { result: { isError: boolean; content: Array<{ text: string }> } };
  assert.equal(rpcBody.result.isError, false);
  assert.equal(rpcBody.result.content[0].text, '{"submissions":[]}');

  // OPTIONS /mcp preserves CORS headers + Allow + Vary while adding security headers and Cache-Control: no-store
  const optRes = await worker.fetch(
    new Request("https://sunstead.org/mcp", {
      method: "OPTIONS",
      headers: { Origin: "https://sunstead.org" },
    }),
    env
  );
  assert.equal(optRes.status, 204);
  assert.equal(optRes.headers.get("Allow"), "POST, OPTIONS");
  assert.equal(optRes.headers.get("Access-Control-Allow-Origin"), "https://sunstead.org");
  assert.equal(optRes.headers.get("Vary"), "Origin");
  assert.equal(optRes.headers.get("Cache-Control"), "no-store");
  assertBaseSecurityHeaders(optRes.headers);

  // GET /mcp -> 405 with Allow + security headers + no-store
  const getRes = await worker.fetch(new Request("https://sunstead.org/mcp", { method: "GET" }), env);
  assert.equal(getRes.status, 405);
  assert.equal(getRes.headers.get("Allow"), "POST, OPTIONS");
  assert.equal(getRes.headers.get("Cache-Control"), "no-store");
  assertBaseSecurityHeaders(getRes.headers);

  // Cross-origin -> 403 with security headers + no-store
  const badOriginRes = await worker.fetch(
    new Request("https://sunstead.org/mcp", {
      method: "POST",
      headers: { Origin: "https://evil.example" },
    }),
    env
  );
  assert.equal(badOriginRes.status, 403);
  assert.equal(badOriginRes.headers.get("Cache-Control"), "no-store");
  assertBaseSecurityHeaders(badOriginRes.headers);
});

test("Worker index.ts streams /api/events without buffering and adds BASE_SECURITY_HEADERS", async () => {
  const worker = await getEdgeWorker();
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  let controller!: ReadableStreamDefaultController<Uint8Array>;
  const stream = new ReadableStream<Uint8Array>({
    start(c) {
      controller = c;
      c.enqueue(encoder.encode("retry: 2000\n: connected\n\n"));
    },
  });

  const env = makeMockEnv(async (req) => {
    assert.equal(new URL(req.url).pathname, "/api/events");
    return new Response(stream, {
      status: 200,
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Access-Control-Allow-Origin": "*",
      },
    });
  });

  // Must resolve immediately even though the SSE stream stays open (proving zero buffering!)
  const res = await worker.fetch(new Request("https://sunstead.org/api/events"), env);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("Content-Type"), "text/event-stream");
  assert.equal(res.headers.get("Cache-Control"), "no-cache");
  assert.equal(res.headers.get("Access-Control-Allow-Origin"), "*");
  assertBaseSecurityHeaders(res.headers);
  assert.equal(res.headers.get("Content-Security-Policy"), null);

  assert.ok(res.body, "expected live ReadableStream body");
  const reader = res.body.getReader();
  const first = await reader.read();
  assert.equal(first.done, false);
  assert.equal(decoder.decode(first.value), "retry: 2000\n: connected\n\n");

  // Push a second live event while connected and verify incremental delivery
  controller.enqueue(encoder.encode('event: ping\ndata: {"ok":true}\n\n'));
  const second = await reader.read();
  assert.equal(second.done, false);
  assert.equal(decoder.decode(second.value), 'event: ping\ndata: {"ok":true}\n\n');

  controller.close();
  const end = await reader.read();
  assert.equal(end.done, true);
});
