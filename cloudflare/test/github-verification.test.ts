import assert from "node:assert/strict";
import test from "node:test";
import { DatabaseSync } from "node:sqlite";
import { startGithubVerification, confirmGithubVerification, clearGithubVerification } from "../src/github_verification.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE contributors(handle TEXT PRIMARY KEY, github TEXT,
    github_verified_handle TEXT, github_verified_at INTEGER, github_challenge TEXT,
    github_challenge_expires INTEGER); INSERT INTO contributors(handle,github) VALUES ('sam','Octocat')`);
  db.exec(clearGithubVerification);
  const sql = {exec: (q, ...args) => ({toArray: () => db.prepare(q).all(...args)})};
  const {body} = startGithubVerification(sql, "sam", 1000);
  const gist = {public: true, owner: {login: "octocat"}, files: {"check.txt": {content: body.challenge}}};
  const confirm = (fetcher = async () => Response.json(gist), clock = () => 1001) =>
    confirmGithubVerification(sql, "sam", "abcd", fetcher, clock);
  return {db,sql,gist,confirm};
}

test("public gist verification consumes the exact challenge once and survives case-only edits", async () => {
  const {db,gist,confirm} = fixture();
  const result = await confirm(async (url, opts) => {
    assert.equal(url, "https://api.github.com/gists/abcd");
    assert.equal(opts.redirect, "error");
    assert.equal(new Headers(opts.headers).has("Authorization"), false);
    return Response.json(gist);
  });
  assert.equal(result.body.github_verified_handle, "Octocat");
  assert.equal((await confirm()).status, 409);
  db.exec("UPDATE contributors SET github='octocat'");
  assert.equal(db.prepare("SELECT github_verified_at FROM contributors").get().github_verified_at, 1001);
  db.exec("UPDATE contributors SET github='other'");
  assert.equal(db.prepare("SELECT github_verified_at FROM contributors").get().github_verified_at, null);
});
test("owner, public visibility, expiry and exact file contents are required", async () => {
  const {gist,confirm} = fixture();
  for (const bad of [{...gist, public:false}, {...gist,owner:{login:"someone"}},
    {...gist,files:{x:{content: gist.files["check.txt"].content + "x"}}}]) {
    assert.equal((await confirm(async () => Response.json(bad))).status, 422);
  }
  assert.equal((await confirm(() => {throw new Error("unexpected fetch")}, () => 1900)).status, 409);
});
test("rotated challenge or changed handle during fetch invalidates the pending confirmation", async () => {
  for (const action of ["rotate","change"]) {
    const {db,sql,gist,confirm} = fixture();
    const result = await confirm(async () => {
      if (action === "rotate") startGithubVerification(sql, "sam", 1001);
      else db.exec("UPDATE contributors SET github='newname'");
      return Response.json(gist);
    });
    assert.equal(result.status, 409);
    assert.equal(db.prepare("SELECT github_verified_handle FROM contributors").get().github_verified_handle, null);
  }
});

test("optional GITHUB_API_TOKEN sends Bearer authorization when configured", async () => {
  const { sql, gist } = fixture();
  let authHeader: string | null = null;
  const result = await confirmGithubVerification(
    sql,
    "sam",
    "abcd",
    async (_url, opts) => {
      authHeader = new Headers(opts?.headers).get("Authorization");
      return Response.json(gist);
    },
    () => 1001,
    "ghp_test_token_123"
  );
  assert.equal(result.status, 200);
  assert.equal(authHeader, "Bearer ghp_test_token_123");
});
