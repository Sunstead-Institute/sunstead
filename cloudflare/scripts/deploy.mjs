#!/usr/bin/env node
/**
 * Sunstead deploy helper.
 *
 *   node scripts/deploy.mjs full   [cf deploy flags...]   # rebuild + roll out the Lean 4 verifier image
 *   node scripts/deploy.mjs worker [cf deploy flags...]   # Worker/hub/UI only; reuse the live image digest
 *   node scripts/deploy.mjs inputs                         # print the verifier-inputs hash and exit
 *
 * Worker-only mode sets SUNSTEAD_VERIFIER_IMAGE to the digest-pinned image that
 * is already running (`cf containers applications list`), so `cloudflare.config.ts`
 * declares `image: { reference }` and `cf deploy` skips the Docker build entirely.
 *
 * Safety: the verifier image bundles the frozen missions and the verifier code
 * (every COPY source in containers/lean4/Dockerfile). If any of those changed,
 * reusing the old image would make the Worker and the verifier disagree about
 * the missions, so Worker-only mode refuses unless the current inputs hash
 * matches the one recorded by the last successful full deploy from this
 * checkout (`.cloudflare/verifier-image.json`, git-ignored). `--force` overrides
 * that check after you have confirmed the image is current by other means.
 */
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CF_ROOT = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(CF_ROOT, "..");
const DOCKERFILE = path.join(CF_ROOT, "containers", "lean4", "Dockerfile");
const DOCKERFILE_V435 = path.join(CF_ROOT, "containers", "lean4-v4.35.0", "Dockerfile");
const DOCKERFILE_V431 = path.join(CF_ROOT, "containers", "lean4-v4.31.0", "Dockerfile");
const RECORD = path.join(CF_ROOT, ".cloudflare", "verifier-image.json");
const APP_NAME = "sunstead-verifier-lean4";
export const VERIFIER_APPS = [
  { name: "sunstead-verifier-lean4", envVar: "SUNSTEAD_VERIFIER_IMAGE", dockerfile: DOCKERFILE },
  { name: "sunstead-verifier-lean4-v435", envVar: "SUNSTEAD_VERIFIER_V435_IMAGE", dockerfile: DOCKERFILE_V435 },
  { name: "sunstead-verifier-lean4-v431", envVar: "SUNSTEAD_VERIFIER_V431_IMAGE", dockerfile: DOCKERFILE_V431 },
];
export const IMAGE_RE = /^registry\.cloudflare\.com\/[A-Za-z0-9._\/-]+@sha256:[0-9a-f]{64}$/;

/** Repo-relative COPY/ADD sources of the verifier image (multi-stage `--from=` copies excluded). */
export function dockerfileInputs(dockerfileText) {
  const sources = [];
  const lines = dockerfileText.replace(/\\\r?\n/g, " ").split(/\r?\n/);
  for (const line of lines) {
    const m = line.trim().match(/^(COPY|ADD)\s+(.*)$/i);
    if (!m) continue;
    const parts = m[2].split(/\s+/).filter(Boolean);
    if (parts.some((p) => p.startsWith("--from="))) continue;
    const args = parts.filter((p) => !p.startsWith("--"));
    sources.push(...args.slice(0, -1));
  }
  return sources;
}

function listFiles(abs) {
  const st = fs.statSync(abs);
  if (st.isFile()) return [abs];
  const out = [];
  for (const entry of fs.readdirSync(abs, { withFileTypes: true })) {
    if (
      entry.name === ".git" ||
      entry.name === ".lake" ||
      entry.name === "__pycache__" ||
      entry.name === ".DS_Store"
    ) {
      continue;
    }
    out.push(...listFiles(path.join(abs, entry.name)));
  }
  return out;
}

/** SHA-256 over the verifier Dockerfile(s) and every file they copy into the image(s), by repo-relative path. */
export function verifierInputsHash(repoRoot = REPO_ROOT, dockerfile = null) {
  const dockerfiles =
    dockerfile === null
      ? VERIFIER_APPS.map((a) => a.dockerfile)
      : Array.isArray(dockerfile)
        ? dockerfile
        : [dockerfile];
  const files = new Set();
  for (const df of dockerfiles) {
    files.add(df);
    for (const src of dockerfileInputs(fs.readFileSync(df, "utf8"))) {
      for (const f of listFiles(path.join(repoRoot, src))) files.add(f);
    }
  }
  const h = crypto.createHash("sha256");
  for (const f of [...files].map((f) => path.relative(repoRoot, f).split(path.sep).join("/")).sort()) {
    h.update(f + "\0");
    h.update(fs.readFileSync(path.join(repoRoot, f)));
    h.update("\0");
  }
  return h.digest("hex");
}

function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { cwd: CF_ROOT, stdio: "inherit", ...opts });
  if (r.error) throw r.error;
  return r.status ?? 1;
}

/** Find the live (or active rollout target) image digest of a verifier application. */
export function imageFromApplications(stdout, appName = APP_NAME) {
  let parsed;
  const re = /^[ \t]*[[{]/gm;
  for (const m of stdout.matchAll(re)) {
    try {
      const candidate = JSON.parse(stdout.slice(m.index));
      if (candidate && typeof candidate === "object") {
        parsed = candidate;
        break;
      }
    } catch {}
  }
  if (parsed === undefined) {
    throw new Error("no JSON in `cf containers applications list` output");
  }
  const apps = Array.isArray(parsed) ? parsed : parsed.result ?? parsed.applications ?? parsed.items ?? [];
  const app = apps.find((a) => a?.name === appName);
  if (!app) throw new Error(`no container application named ${appName} (has a full deploy run yet?)`);
  const targetImage =
    app.target?.configuration?.image ?? app.rollout?.target_configuration?.image;
  if (typeof targetImage === "string" && targetImage.length > 0) {
    return targetImage;
  }
  if (typeof app.active_rollout_id === "string" && app.active_rollout_id.length > 0) {
    const envVar = VERIFIER_APPS.find((a) => a.name === appName)?.envVar ?? "SUNSTEAD_VERIFIER_IMAGE";
    throw new Error(
      `${appName} has an active container rollout (${app.active_rollout_id}) and its target image is not in ` +
        "`cf containers applications list` yet (configuration.image may still report the pre-rollout digest). " +
        `Wait for the rollout to finish or pass ${envVar}=<registry.cloudflare.com/...@sha256:...> explicitly.`,
    );
  }
  const image = app.configuration?.image ?? app.image;
  if (typeof image !== "string") throw new Error(`${appName} has no configuration.image`);
  return image;
}

/** Build `cf deploy` args without duplicating `--containers-rollout` if caller supplied it. */
export function buildCfDeployArgs(cfArgs) {
  const hasRollout = cfArgs.some(
    (a) => a === "--containers-rollout" || a.startsWith("--containers-rollout=")
  );
  return hasRollout
    ? ["cf", "deploy", ...cfArgs]
    : ["cf", "deploy", "--containers-rollout", "immediate", ...cfArgs];
}

function liveImage(appName = APP_NAME) {
  const r = spawnSync("npx", ["cf", "containers", "applications", "list", "--name", appName], {
    cwd: CF_ROOT,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  });
  if (r.status !== 0) throw new Error("`cf containers applications list` failed (are you logged in?)");
  return imageFromApplications(r.stdout, appName);
}

function main(argv) {
  const [mode, ...rest] = argv;
  // `--force` only overrides the worker-mode inputs-hash check; in `full` mode,
  // forward every flag untouched to `cf deploy`.
  const force = mode === "worker" && rest.includes("--force");
  const cfArgs = mode === "worker" ? rest.filter((a) => a !== "--force") : rest;
  const inputs = verifierInputsHash();

  if (mode === "inputs") {
    console.log(inputs);
    return 0;
  }
  if (mode !== "full" && mode !== "worker") {
    console.error("usage: node scripts/deploy.mjs full|worker|inputs [--force] [cf deploy flags...]");
    return 2;
  }

  if (run("node", ["scripts/sync-assets.mjs"]) !== 0) return 1;
  const deployArgs = buildCfDeployArgs(cfArgs);
  const dryRun = cfArgs.includes("--dry-run");

  if (mode === "full") {
    const env = { ...process.env };
    for (const app of VERIFIER_APPS) delete env[app.envVar]; // a full deploy always builds from Dockerfiles
    const status = run("npx", deployArgs, { env });
    if (status === 0 && !dryRun) {
      fs.mkdirSync(path.dirname(RECORD), { recursive: true });
      fs.writeFileSync(RECORD, JSON.stringify({ inputs, deployedAt: new Date().toISOString() }, null, 2) + "\n");
      console.log(`Recorded verifier inputs ${inputs.slice(0, 12)}… in ${path.relative(CF_ROOT, RECORD)}`);
    }
    return status;
  }

  // Worker-only.
  let recorded = null;
  try {
    recorded = JSON.parse(fs.readFileSync(RECORD, "utf8")).inputs;
  } catch {}
  if (recorded !== inputs && !force) {
    console.error(
      recorded
        ? `Verifier inputs changed since the last full deploy (${recorded.slice(0, 12)}… → ${inputs.slice(0, 12)}…).\n` +
            "missions/ or the verifier code differs from the live image: run `npm run deploy` instead."
        : "No record of a full deploy from this checkout, so the live image cannot be matched to these missions.\n" +
            "Run `npm run deploy` once, or pass --force if you have confirmed the live image is built from this commit.",
    );
    return 1;
  }
  const env = { ...process.env };
  for (const app of VERIFIER_APPS) {
    const image = process.env[app.envVar] || liveImage(app.name);
    if (!IMAGE_RE.test(image)) {
      console.error(`Refusing ${app.name} image ${JSON.stringify(image)}: expected registry.cloudflare.com/...@sha256:<64 hex>.`);
      return 1;
    }
    env[app.envVar] = image;
    console.log(`Worker-only deploy reusing ${app.name}: ${image}`);
  }
  return run("npx", deployArgs, { env });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (e) {
    console.error(String(e?.message ?? e));
    process.exit(1);
  }
}
