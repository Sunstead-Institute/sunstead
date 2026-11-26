import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { z } from "zod";

const MAX_PATCH_CHARS = 512 * 1024;
const segment = z.string().max(256).regex(/^[A-Za-z0-9_-]+$/);
const submissionId = z.string().max(128).regex(/^[A-Za-z0-9-]+$/);
const contributorHandleFilter = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._-]{1,35}$/);
const mission = { mission_id: segment };
const task = { ...mission, task_id: segment };
const missions = "/api/missions";

export async function handleMcp(request: Request, fetchHub: (req: Request) => Promise<Response>) {
  const url = new URL(request.url);
  const origin = request.headers.get("Origin");
  if (origin !== null && origin !== url.origin) {
    return new Response("Forbidden", { status: 403, headers: { "Cache-Control": "no-store" } });
  }
  if (request.method === "OPTIONS") {
    const headers: Record<string, string> = {
      Allow: "POST, OPTIONS",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, Mcp-Session-Id, MCP-Protocol-Version",
      "Access-Control-Max-Age": "86400",
      "Cache-Control": "no-store",
    };
    if (origin !== null) {
      headers["Access-Control-Allow-Origin"] = origin;
      headers.Vary = "Origin";
    }
    return new Response(null, { status: 204, headers });
  }
  if (request.method !== "POST") {
    return new Response(null, {
      status: 405,
      headers: { Allow: "POST, OPTIONS", "Cache-Control": "no-store" },
    });
  }

  // Each request owns its server and transport. Credentials and responses never span requests.
  const server = new McpServer({ name: "sunstead", version: "1.0.0" });
  async function forward(path: string, body?: object, method?: "GET" | "POST" | "PATCH") {
    const headers = new Headers();
    for (const key of ["Authorization", "CF-Connecting-IP", "X-Forwarded-For"]) {
      const value = request.headers.get(key);
      if (value !== null) headers.set(key, value);
    }
    if (body) headers.set("Content-Type", "application/json");
    try {
      const response = await fetchHub(new Request(new URL(path, url), {
        method: method ?? (body ? "POST" : "GET"), headers, body: body ? JSON.stringify(body) : undefined,
      }));
      const text = await response.text();
      return {
        isError: !response.ok,
        content: [{ type: "text" as const, text: response.ok ? text : `HTTP ${response.status}: ${text}` }],
      };
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return {
        isError: true,
        content: [{ type: "text" as const, text: `Hub request failed: ${message}` }],
      };
    }
  }
  function taskPath(args: { mission_id: string; task_id: string }) {
    return `${missions}/${args.mission_id}/tasks/${args.task_id}`;
  }
  function withQuery(
    basePath: string,
    params: Record<string, string | number | boolean | undefined>
  ): string {
    const sp = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) {
      if (v === undefined) continue;
      if (typeof v === "string" && v.trim() === "") continue;
      sp.set(k, String(v));
    }
    const qs = sp.toString();
    return qs ? `${basePath}?${qs}` : basePath;
  }
  server.registerTool(
    "register_contributor",
    {
      description: "Register a new contributor handle and receive a one-time SUNSTEAD_API_KEY.",
      inputSchema: {
        handle: z.string().min(1).max(64),
        display_name: z.string().max(128).optional(),
        github: z.string().max(64).optional(),
        x: z.string().max(32).optional(),
        linkedin: z.string().max(128).optional(),
      },
    },
    args => forward("/api/contributors/register", args, "POST")
  );
  server.registerTool("get_me", { description: "Inspect your authenticated contributor profile and link visibility.", inputSchema: {} },
    () => forward("/api/me", undefined, "GET"));
  server.registerTool(
    "list_missions",
    {
      description:
        "List active missions and frontier task IDs, with optional filtering by mode, tier, open_conjecture, toolchain, has_frontier, or search query.",
      inputSchema: {
        mode: z.enum(["dag", "hillclimb"]).optional(),
        tier: z.number().int().min(1).max(2).optional(),
        open_conjecture: z.boolean().optional(),
        toolchain: z.string().max(128).optional(),
        has_frontier: z.boolean().optional(),
        q: z.string().max(200).optional(),
      },
    },
    args => forward(withQuery(missions, args), undefined, "GET")
  );
  server.registerTool(
    "get_open_frontier",
    {
      description:
        "Find ready, non-disputed frontier tasks across all non-demo missions in one call, ordered unclaimed-first and Tier 1 before Tier 2.",
      inputSchema: {
        unclaimed: z.boolean().optional(),
        mode: z.enum(["dag", "hillclimb"]).optional(),
        tier: z.number().int().min(1).max(2).optional(),
        open_conjecture: z.boolean().optional(),
        toolchain: z.string().max(128).optional(),
        mission: segment.optional(),
        q: z.string().max(200).optional(),
        limit: z.number().int().min(1).max(200).optional(),
        offset: z.number().int().min(0).optional(),
      },
    },
    args => forward(withQuery("/api/frontier", args), undefined, "GET")
  );
  server.registerTool("get_mission_frontier", { description: "Inspect mission tasks and the current frontier.", inputSchema: mission },
    ({ mission_id }) => forward(`${missions}/${mission_id}`));
  server.registerTool("get_task_files", { description: "Read a task's target and frozen files.", inputSchema: task },
    args => forward(`${taskPath(args)}/files`));
  server.registerTool("get_verified_proof", { description: "Read the task's most recent accepted proof.", inputSchema: task },
    args => forward(`${taskPath(args)}/proof`));
  server.registerTool("claim_task", { description: "Claim a contributor lease.", inputSchema: { ...task, lease_seconds: z.number().int().optional() } },
    args => forward(`${taskPath(args)}/claim`, { lease_seconds: args.lease_seconds }));
  server.registerTool("release_task", { description: "Release your active lease.", inputSchema: task },
    args => forward(`${taskPath(args)}/release`, {}));
  server.registerTool(
    "submit_patch",
    {
      description:
        "Submit a unified git diff for verification. Defaults to async mode (returns HTTP 202 + submission_id immediately to avoid MCP timeouts; poll get_submission_status). Pass async: false to wait synchronously.",
      inputSchema: { ...task, patch: z.string().max(MAX_PATCH_CHARS), async: z.boolean().optional() },
    },
    args =>
      forward(
        `${taskPath(args)}/submit${args.async === false ? "" : "?async=1"}`,
        { patch: args.patch }
      )
  );
  server.registerTool(
    "list_submissions",
    {
      description:
        "List recent verification submissions across the hub, with optional filtering by mission, task, contributor, status, or limit.",
      inputSchema: {
        mission: segment.optional(),
        task: segment.optional(),
        contributor: contributorHandleFilter.optional(),
        status: z.enum(["verifying", "accepted", "rejected", "error"]).optional(),
        limit: z.number().int().min(1).max(200).optional(),
      },
    },
    args => forward(withQuery("/api/submissions", args), undefined, "GET")
  );
  server.registerTool(
    "get_submission_status",
    {
      description: "Poll the status and verdict (verifying, accepted, rejected, error) of a submission_id.",
      inputSchema: { submission_id: submissionId },
    },
    ({ submission_id }) => forward(`/api/submissions/${submission_id}`, undefined, "GET")
  );
  server.registerTool(
    "update_profile",
    {
      description: "Update or clear your contributor display_name and GitHub, X, or LinkedIn handles (handle only, never URLs).",
      inputSchema: {
        display_name: z.string().max(128).nullable().optional(),
        github: z.string().max(64).nullable().optional(),
        x: z.string().max(32).nullable().optional(),
        linkedin: z.string().max(128).nullable().optional(),
      },
    },
    args => forward("/api/me", args, "PATCH")
  );
  server.registerTool(
    "decompose_task",
    {
      description:
        "Propose a kernel-verified v2 decomposition (L_1 ∧ ... ∧ L_k → T, 2-6 subgoals, max depth 2) on a decomposition-enabled DAG task. Requires Phase 1 allowlist membership.",
      inputSchema: {
        ...task,
        decomp_id: z.string().regex(/^[a-z0-9][a-z0-9_]{0,23}$/).optional(),
        subgoals: z.array(
          z.object({
            id: z.string().regex(/^[a-z][a-z0-9_]{1,47}$/),
            title: z.string().min(1).max(200),
            statement: z.string().min(1).max(4096),
          })
        ).min(2).max(6),
        reduction_file: z.string().min(1).max(256),
        reduction_theorem: z.string().min(1).max(256),
        patch: z.string().max(MAX_PATCH_CHARS),
      },
    },
    ({ mission_id, task_id, ...body }) =>
      forward(`${taskPath({ mission_id, task_id })}/decompose`, body, "POST")
  );
  server.registerTool(
    "refute_task",
    {
      description:
        "Submit a kernel-verified disproof (¬ T on ANY open DAG root task across all missions, or ¬ L_i on a spawned subgoal). Open to all registered contributors with no allowlist; resolves open conjectures (open_conjecture: true) for full Tier 1 points, removes false root tasks from the frontier, or invalidates broken decompositions and awards a refutation bounty. Defaults to async mode (HTTP 202 + submission_id; poll get_submission_status). Pass async: false to wait synchronously.",
      inputSchema: {
        ...task,
        refute_file: z.string().max(256).optional(),
        refute_theorem: z.string().min(1).max(256),
        patch: z.string().max(MAX_PATCH_CHARS),
        async: z.boolean().optional(),
      },
    },
    ({ mission_id, task_id, async: isAsync, ...body }) =>
      forward(
        `${taskPath({ mission_id, task_id })}/refute${isAsync === false ? "" : "?async=1"}`,
        body,
        "POST"
      )
  );

  const transport = new WebStandardStreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  await server.connect(transport);
  try {
    return await transport.handleRequest(request);
  } finally {
    await server.close();
  }
}
