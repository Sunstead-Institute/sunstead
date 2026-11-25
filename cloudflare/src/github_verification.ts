// A challenge belongs to one contributor and one GitHub login. Each start rotates it.
export const clearGithubVerification = `CREATE TRIGGER IF NOT EXISTS clear_github_verification
  AFTER UPDATE OF github ON contributors WHEN lower(OLD.github) IS NOT lower(NEW.github)
  BEGIN UPDATE contributors SET github_verified_handle=NULL, github_verified_at=NULL,
    github_challenge=NULL, github_challenge_expires=NULL WHERE handle=NEW.handle; END`;

type Storage = Pick<SqlStorage, "exec">;
type Result = { status: number; body: Record<string, unknown> };
const failure = (status: number, error: string): Result => ({ status, body: { error } });

export function startGithubVerification(sql: Storage, handle: string, now: number): Result {
  const challenge = `sunstead-verify:${handle}:${crypto.randomUUID()}`;
  const expires = now + 900;
  const [row] = sql.exec<{github: string}>(`UPDATE contributors SET github_challenge=?,
    github_challenge_expires=? WHERE handle=? AND github IS NOT NULL RETURNING github`,
    challenge, expires, handle).toArray();
  if (!row) return failure(409, "Set your GitHub handle first");
  return { status: 200, body: { github: row.github, challenge, expires_at: expires } };
}

export async function confirmGithubVerification(sql: Storage, handle: string, id: unknown,
    fetchGist: typeof fetch = fetch, clock = () => Math.floor(Date.now() / 1000)): Promise<Result> {
  if (typeof id !== "string" || !/^[0-9a-f]{1,64}$/i.test(id)) return failure(400, "Expected a GitHub Gist ID");
  const [pending] = sql.exec<{github: string; github_challenge: string}>(
    `SELECT github, github_challenge FROM contributors WHERE handle=? AND github IS NOT NULL
     AND github_challenge IS NOT NULL AND github_challenge_expires>?`, handle, clock()).toArray();
  if (!pending) return failure(409, "Start a new verification challenge");
  try {
    const response = await fetchGist(`https://api.github.com/gists/${id}`, {
      headers: { Accept: "application/vnd.github+json", "User-Agent": "Sunstead-Gist-Verification" },
      redirect: "error", signal: AbortSignal.timeout(8000),
    });
    if (response.status === 404) return failure(422, "Public gist not found");
    if (!response.ok || !response.body) return failure(503, "GitHub is unavailable. Retry later");
    // Bound memory even for large gists delivered without Content-Length.
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let size = 0;
    let json = "";
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > 256 * 1024) {
        await reader.cancel();
        return failure(422, "Use a small public gist containing the challenge");
      }
      json += decoder.decode(chunk.value, { stream: true });
    }
    const gist = JSON.parse(json + decoder.decode());
    const files = Object.values(gist.files ?? {}) as {content?: string; truncated?: boolean}[];
    if (gist.public !== true || gist.owner?.login?.toLowerCase() !== pending.github.toLowerCase() ||
        !files.some(f => !f?.truncated && typeof f?.content === "string" &&
          f.content.split(/\r?\n/).includes(pending.github_challenge))) {
      return failure(422, "The public gist must contain your exact challenge on its own line and belong to your configured GitHub account");
    }
  } catch {
    return failure(503, "Could not read the gist from GitHub. Retry later");
  }
  const now = clock();
  const updated = sql.exec(`UPDATE contributors SET github_verified_handle=github, github_verified_at=?,
    github_challenge=NULL, github_challenge_expires=NULL WHERE handle=? AND github=? COLLATE NOCASE
    AND github_challenge=? AND github_challenge_expires>? RETURNING github`,
    now, handle, pending.github, pending.github_challenge, now).toArray();
  if (!updated.length) return failure(409, "Challenge expired or changed. Start a new challenge");
  return { status: 200, body: { github_verified_handle: updated[0].github, github_verified_at: now } };
}
