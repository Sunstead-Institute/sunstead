import { handleMcp } from "./mcp";
import { Lean4Verifier, Lean4V435Verifier, Lean4V431Verifier } from "./containers";
import { buildEdgeSecurityHeaders, isLedgerPagePath } from "./core";
import { STATIC_ASSETS } from "./generated/static";
import { SunsteadHub, type HubEnv } from "./hub_do";

export { SunsteadHub, Lean4Verifier, Lean4V435Verifier, Lean4V431Verifier };

export default {
  async fetch(request: Request, env: HubEnv): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // Canonicalize www.sunstead.org -> https://sunstead.org
    if (url.hostname === "www.sunstead.org") {
      return new Response(null, {
        status: 301,
        headers: {
          Location: `https://sunstead.org${url.pathname}${url.search}`,
          ...buildEdgeSecurityHeaders(),
        },
      });
    }

    // Serve Sunstead Foundation static UI directly at Cloudflare's edge.
    if ((request.method === "GET" || request.method === "HEAD") && path in STATIC_ASSETS) {
      const asset = STATIC_ASSETS[path];
      return new Response(request.method === "HEAD" ? null : asset.body, {
        headers: {
          "Content-Type": asset.contentType,
          "Cache-Control": asset.contentType.startsWith("text/html")
            ? "public, max-age=60"
            : "public, max-age=300",
          ...buildEdgeSecurityHeaders(asset.contentType),
        },
      });
    }

    // Ledger pages: /proofs and /proofs/<patch sha256> share one page; app.js
    // reads the hash from the URL and loads it from /api/proofs.
    if ((request.method === "GET" || request.method === "HEAD") && isLedgerPagePath(path)) {
      const asset = STATIC_ASSETS["/proofs.html"];
      return new Response(request.method === "HEAD" ? null : asset.body, {
        headers: {
          "Content-Type": asset.contentType,
          "Cache-Control": "public, max-age=60",
          ...buildEdgeSecurityHeaders(asset.contentType),
        },
      });
    }

    if (path === "/mcp") {
      const hub = env.HUB.getByName("sunstead-global-v1");
      return handleMcp(request, req => hub.fetch(req));
    }

    // Route `/join.txt` and `/api/*` into the persistent SQLite Durable Object Hub.
    if (path === "/join.txt" || path.startsWith("/api/")) {
      const hub = env.HUB.getByName("sunstead-global-v1");
      const forwardReq =
        request.method === "HEAD" && path === "/join.txt"
          ? new Request(request.url, { method: "GET", headers: request.headers })
          : request;
      const resp = await hub.fetch(forwardReq);
      if (path === "/api/events") return resp;
      const headers = new Headers(resp.headers);
      for (const [k, v] of Object.entries(buildEdgeSecurityHeaders(resp.headers.get("Content-Type")))) {
        if (!headers.has(k)) headers.set(k, v);
      }
      return new Response(request.method === "HEAD" ? null : resp.body, {
        status: resp.status,
        statusText: resp.statusText,
        headers,
      });
    }

    return new Response("Not Found", {
      status: 404,
      headers: buildEdgeSecurityHeaders("text/plain; charset=utf-8"),
    });
  },
};
