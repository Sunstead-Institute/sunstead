import { handleMcp } from "./mcp";
import { Lean4Verifier, Lean4V435Verifier, Lean4V431Verifier } from "./containers";
import { buildEdgeSecurityHeaders, isLedgerPagePath } from "./core";
import { STATIC_ASSETS } from "./generated/static";
import { SunsteadHub, type HubEnv } from "./hub_do";

export { SunsteadHub, Lean4Verifier, Lean4V435Verifier, Lean4V431Verifier };

const utf8Encoder = new TextEncoder();
const assetEtagCache = new WeakMap<{ body: string }, string>();

function computeWeakEtag(body: string): string {
  const bytes = utf8Encoder.encode(body);
  let hash = 0x811c9dc5;
  for (let i = 0; i < bytes.length; i++) {
    hash ^= bytes[i];
    hash = Math.imul(hash, 0x01000193);
  }
  return `W/"${(hash >>> 0).toString(16).padStart(8, "0")}-${bytes.byteLength}"`;
}

function getAssetEtag(asset: { body: string }): string {
  let etag = assetEtagCache.get(asset);
  if (!etag) {
    etag = computeWeakEtag(asset.body);
    assetEtagCache.set(asset, etag);
  }
  return etag;
}

function stripWeakPrefix(tag: string): string {
  return tag.startsWith("W/") ? tag.slice(2) : tag;
}

function ifNoneMatchMatches(ifNoneMatch: string | null, currentEtag: string): boolean {
  if (!ifNoneMatch) return false;
  const trimmed = ifNoneMatch.trim();
  if (!trimmed) return false;
  if (trimmed === "*") return true;
  const currentOpaque = stripWeakPrefix(currentEtag);
  let i = 0;
  while (i < trimmed.length) {
    while (i < trimmed.length && (trimmed[i] === " " || trimmed[i] === "\t" || trimmed[i] === ",")) {
      i++;
    }
    if (i >= trimmed.length) break;
    const start = i;
    let inQuotes = false;
    while (i < trimmed.length) {
      const ch = trimmed[i];
      if (ch === '"') inQuotes = !inQuotes;
      else if (ch === "," && !inQuotes) break;
      i++;
    }
    const candidate = trimmed.slice(start, i).trim();
    if (candidate === "*") return true;
    if (/^(?:W\/)?"[^"]*"$/.test(candidate) && stripWeakPrefix(candidate) === currentOpaque) {
      return true;
    }
  }
  return false;
}

function serveStaticAsset(
  request: Request,
  asset: { contentType: string; body: string },
  cacheControl: string
): Response {
  const etag = getAssetEtag(asset);
  const securityHeaders = buildEdgeSecurityHeaders(asset.contentType);
  if (ifNoneMatchMatches(request.headers.get("If-None-Match"), etag)) {
    return new Response(null, {
      status: 304,
      headers: {
        ETag: etag,
        "Cache-Control": cacheControl,
        ...securityHeaders,
      },
    });
  }
  return new Response(request.method === "HEAD" ? null : asset.body, {
    headers: {
      "Content-Type": asset.contentType,
      "Cache-Control": cacheControl,
      ETag: etag,
      ...securityHeaders,
    },
  });
}

function withEdgeSecurityHeaders(
  resp: Response,
  opts?: { stripBody?: boolean; defaultCacheControl?: string }
): Response {
  const headers = new Headers(resp.headers);
  for (const [k, v] of Object.entries(buildEdgeSecurityHeaders(resp.headers.get("Content-Type")))) {
    if (!headers.has(k)) headers.set(k, v);
  }
  if (opts?.defaultCacheControl && !headers.has("Cache-Control")) {
    headers.set("Cache-Control", opts.defaultCacheControl);
  }
  return new Response(opts?.stripBody ? null : resp.body, {
    status: resp.status,
    statusText: resp.statusText,
    headers,
  });
}

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

    // Serve Sunstead Foundation static UI & /proofs ledger pages directly at Cloudflare's edge.
    const isKnownStatic = Object.prototype.hasOwnProperty.call(STATIC_ASSETS, path);
    if (isKnownStatic || isLedgerPagePath(path)) {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("Method Not Allowed", {
          status: 405,
          headers: {
            Allow: "GET, HEAD",
            "Content-Type": "text/plain; charset=utf-8",
            ...buildEdgeSecurityHeaders("text/plain; charset=utf-8"),
          },
        });
      }
      const asset = isKnownStatic ? STATIC_ASSETS[path] : STATIC_ASSETS["/proofs.html"];
      const cacheControl =
        !isKnownStatic || asset.contentType.startsWith("text/html")
          ? "public, max-age=60"
          : "public, max-age=300";
      return serveStaticAsset(request, asset, cacheControl);
    }

    if (path === "/mcp") {
      const hub = env.HUB.getByName("sunstead-global-v1");
      const resp = await handleMcp(request, (req) => hub.fetch(req));
      return withEdgeSecurityHeaders(resp, { defaultCacheControl: "no-store" });
    }

    // Route `/join.txt` and `/api/*` into the persistent SQLite Durable Object Hub.
    if (path === "/join.txt" || path.startsWith("/api/")) {
      const hub = env.HUB.getByName("sunstead-global-v1");
      const forwardReq =
        request.method === "HEAD" && path === "/join.txt"
          ? new Request(request.url, { method: "GET", headers: request.headers })
          : request;
      const resp = await hub.fetch(forwardReq);
      // Preserve live SSE stream without buffering while still applying edge security headers.
      if (path === "/api/events") return withEdgeSecurityHeaders(resp);
      return withEdgeSecurityHeaders(resp, { stripBody: request.method === "HEAD" });
    }

    return new Response("Not Found", {
      status: 404,
      headers: buildEdgeSecurityHeaders("text/plain; charset=utf-8"),
    });
  },
};
