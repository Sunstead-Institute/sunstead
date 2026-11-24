import { Lean4Verifier, RustVerifier } from "./containers";
import { STATIC_ASSETS } from "./generated/static";
import { SunsteadHub, type HubEnv } from "./hub_do";

export { SunsteadHub, Lean4Verifier, RustVerifier };

const SECURITY_HEADERS: Record<string, string> = {
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "strict-origin-when-cross-origin",
};

export default {
  async fetch(request: Request, env: HubEnv): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // Serve Sunstead Foundation static UI directly at Cloudflare's edge.
    if (request.method === "GET" && path in STATIC_ASSETS) {
      const asset = STATIC_ASSETS[path];
      return new Response(asset.body, {
        headers: {
          "Content-Type": asset.contentType,
          "Cache-Control": path === "/" ? "public, max-age=60" : "public, max-age=300",
          ...SECURITY_HEADERS,
        },
      });
    }

    // Route `/join.txt` and `/api/*` into the persistent SQLite Durable Object Hub.
    if (path === "/join.txt" || path.startsWith("/api/")) {
      const hub = env.HUB.getByName("sunstead-global-v1");
      const resp = await hub.fetch(request);
      if (path === "/api/events") return resp;
      const headers = new Headers(resp.headers);
      for (const [k, v] of Object.entries(SECURITY_HEADERS)) {
        if (!headers.has(k)) headers.set(k, v);
      }
      return new Response(resp.body, {
        status: resp.status,
        statusText: resp.statusText,
        headers,
      });
    }

    return new Response("Not Found", { status: 404, headers: SECURITY_HEADERS });
  },
};
