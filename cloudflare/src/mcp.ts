import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { z } from "zod";

const segment = z.string().regex(/^[A-Za-z0-9_-]+$/);
const mission = { mission_id: segment };
const task = { ...mission, task_id: segment };
const missions = "/api/missions";

export async function handleMcp(request: Request, fetchHub: (req: Request) => Promise<Response>) {
  const url = new URL(request.url);
  const origin = request.headers.get("Origin");
  if (origin !== null && origin !== url.origin) return new Response("Forbidden", { status: 403 });
  if (request.method !== "POST") return new Response(null, { status: 405, headers: { Allow: "POST" } });

  // Each request owns its server and transport. Credentials and responses never span requests.
  const server = new McpServer({ name: "sunstead", version: "1.0.0" });
  async function forward(path: string, body?: object, method?: "GET" | "POST" | "PATCH") {
    const headers = new Headers();
    for (const key of ["Authorization", "CF-Connecting-IP", "X-Forwarded-For"]) {
      const value = request.headers.get(key);
      if (value !== null) headers.set(key, value);
    }
    if (body) headers.set("Content-Type", "application/json");
    const response = await fetchHub(new Request(new URL(path, url), {
      method: method ?? (body ? "POST" : "GET"), headers, body: body ? JSON.stringify(body) : undefined,
    }));
    const text = await response.text();
    return {
      isError: !response.ok,
      content: [{ type: "text" as const, text: response.ok ? text : `HTTP ${response.status}: ${text}` }],
    };
  }
  function taskPath(args: { mission_id: string; task_id: string }) {
    return `${missions}/${args.mission_id}/tasks/${args.task_id}`;
  }
  server.registerTool("list_missions", { description: "List active missions and frontier task IDs.", inputSchema: {} },
    () => forward(missions));
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
  server.registerTool("submit_patch", { description: "Submit a unified git diff for verification.", inputSchema: { ...task, patch: z.string() } },
    args => forward(`${taskPath(args)}/submit`, { patch: args.patch }));
  server.registerTool(
    "update_profile",
    {
      description: "Update or clear your contributor display_name and GitHub, X, or LinkedIn handles (handle only, never URLs).",
      inputSchema: {
        display_name: z.string().nullable().optional(),
        github: z.string().nullable().optional(),
        x: z.string().nullable().optional(),
        linkedin: z.string().nullable().optional(),
      },
    },
    args => forward("/api/me", args, "PATCH")
  );

  const transport = new WebStandardStreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  await server.connect(transport);
  try {
    return await transport.handleRequest(request);
  } finally {
    await server.close();
  }
}
