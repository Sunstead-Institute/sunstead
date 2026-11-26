#!/usr/bin/env node
/**
 * Syncs `../web/*` and `../missions/*` (manifests + frozen spec SHA-256 hashes +
 * deduplicated seed files) into `src/generated/` so `web/` and `missions/` remain
 * the single source of truth while staying well within Cloudflare Workers bundle
 * and cold-start budgets at 50+ missions / 1,000+ tasks.
 */
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const CF_ROOT = path.resolve(__dirname, "..");
export const REPO_ROOT = path.resolve(CF_ROOT, "..");
export const GEN_DIR = path.join(CF_ROOT, "src", "generated");

// Cloudflare Workers compressed script size limits: 3 MiB Free / 10 MiB Paid.
export const WORKER_FREE_GZ_LIMIT_BYTES = 3 * 1024 * 1024;
export const WORKER_PAID_GZ_LIMIT_BYTES = 10 * 1024 * 1024;
export const DEFAULT_MAX_ASSETS_GZ_BYTES = 9 * 1024 * 1024;

// ---------------------------------------------------------------------------
// Deterministic glob matcher (must match globMatches in src/core.ts)

export function segmentMatches(pat, seg) {
  const dp = Array.from({ length: pat.length + 1 }, () =>
    Array(seg.length + 1).fill(false)
  );
  dp[0][0] = true;
  for (let i = 1; i <= pat.length; i++) {
    if (pat[i - 1] === "*") dp[i][0] = dp[i - 1][0];
  }
  for (let i = 1; i <= pat.length; i++) {
    for (let j = 1; j <= seg.length; j++) {
      if (pat[i - 1] === "*") {
        dp[i][j] = dp[i - 1][j] || dp[i][j - 1];
      } else if (pat[i - 1] === "?" || pat[i - 1] === seg[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      }
    }
  }
  return dp[pat.length][seg.length];
}

export function matchSegments(pat, p) {
  if (pat.length === 0 && p.length === 0) return true;
  if (pat[0] === "**") {
    return matchSegments(pat.slice(1), p) || (p.length > 0 && matchSegments(pat, p.slice(1)));
  }
  if (pat.length > 0 && p.length > 0) {
    return segmentMatches(pat[0], p[0]) && matchSegments(pat.slice(1), p.slice(1));
  }
  return false;
}

export function globMatches(pattern, relPath) {
  const patSegs = pattern.split("/").filter(Boolean);
  const pathSegs = relPath.split("/").filter(Boolean);
  return matchSegments(patSegs, pathSegs);
}

export function walkFiles(dir, base = dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if ([".git", "target", ".lake"].includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkFiles(full, base, acc);
    } else if (entry.isFile()) {
      acc.push({
        rel: path.relative(base, full).split(path.sep).join("/"),
        abs: full,
      });
    }
  }
  return acc;
}

export function computeFilesSha256(files) {
  const sorted = [...files].sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
  const hash = crypto.createHash("sha256");
  for (const f of sorted) {
    const bytes = fs.readFileSync(f.abs);
    const lenBuf = Buffer.alloc(8);
    lenBuf.writeBigUInt64LE(BigInt(bytes.length));
    hash.update(Buffer.from(f.rel, "utf8"));
    hash.update(Buffer.from([0]));
    hash.update(lenBuf);
    hash.update(Buffer.from([0]));
    hash.update(bytes);
    hash.update(Buffer.from("\n", "utf8"));
  }
  return `sha256:${hash.digest("hex")}`;
}

export function computeSpecSha256(missionDir, frozenPaths) {
  const files = walkFiles(missionDir).filter((f) =>
    frozenPaths.some((pat) => globMatches(pat, f.rel))
  );
  return computeFilesSha256(files);
}

export function computeSeedTreeSha256(missionDir) {
  return computeFilesSha256(walkFiles(missionDir));
}

/**
 * Batch-extract classic Lean verifier contracts (`lib_root`, `statement_preamble`,
 * and per-task `module`/`theorem`/`statement`) across all missions in ONE Python
 * invocation instead of spawning N separate Python processes.
 */
export function extractVerifyContracts(verifyPaths) {
  const existing = verifyPaths.filter((p) => fs.existsSync(p));
  if (existing.length === 0) return {};
  const py = `
import ast, json, sys
out = {}
for path in sys.argv[1:]:
    try:
        src = open(path, "r", encoding="utf-8").read()
        tree = ast.parse(src)
    except Exception:
        out[path] = None
        continue
    vals = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name) and t.id in ("LIB_ROOT", "STATEMENT_PREAMBLE", "TASKS", "FROZEN_FILES"):
                    try:
                        vals[t.id] = ast.literal_eval(node.value)
                    except Exception:
                        pass
    if "LIB_ROOT" not in vals or not isinstance(vals.get("TASKS"), dict):
        out[path] = None
        continue
    tasks = {}
    for tid, spec in vals["TASKS"].items():
        if isinstance(spec, dict) and isinstance(spec.get("module"), str) and isinstance(spec.get("theorem"), str):
            tasks[tid] = {
                "module": spec["module"],
                "theorem": spec["theorem"],
                "statement": spec.get("statement", ""),
            }
    out[path] = {
        "lib_root": vals["LIB_ROOT"],
        "statement_preamble": vals.get("STATEMENT_PREAMBLE", "") or "",
        "frozen_lean_modules": [
            p[:-5].replace("/", ".")
            for p in (vals.get("FROZEN_FILES") or [])
            if isinstance(p, str) and p.endswith(".lean")
        ],
        "tasks": tasks,
    }
print(json.dumps(out))
`;
  try {
    const stdout = execFileSync("python3", ["-c", py, ...existing], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    }).trim();
    return stdout ? JSON.parse(stdout) : {};
  } catch {
    return {};
  }
}

export function resolveVerifierKindForSync(dirName, manifest) {
  const image = (manifest.verifier?.image || "").trim();
  const toolchain = (manifest.verifier?.toolchain || "").trim();
  if (toolchain) {
    if (toolchain === "leanprover/lean4:v4.36.0") return "lean4";
    if (toolchain === "leanprover/lean4:v4.35.0") return "lean4-v4.35.0";
    if (toolchain === "leanprover/lean4:v4.31.0") return "lean4-v4.31.0";
    throw new Error(`unsupported verifier toolchain in ${dirName}: ${toolchain}`);
  }
  if (image.includes("lean4-v4.35.0")) return "lean4-v4.35.0";
  if (image.includes("lean4-v4.31.0")) return "lean4-v4.31.0";
  if (image.includes("lean4")) return "lean4";
  throw new Error(`unsupported verifier image in ${dirName}: ${image} (hub is Lean 4 only)`);
}

/**
 * Determine whether a mission file should be embedded in the Worker bundle for
 * `GET /api/missions/:id/tasks/:task/files` and decomposition assembly.
 *
 * Excludes `verify` and `sunstead.json` (already structured elsewhere) and any
 * non-frozen, non-target files (e.g. unreferenced LICENSE/README copies that
 * `buildTaskFilesView` never serves; full bundles still ship them from the
 * verifier container's `/missions/<id>/` directory).
 */
export function isWorkerServedSeedFile(relPath, manifest) {
  if (relPath === "verify" || relPath === "sunstead.json") return false;
  const frozenPaths = Array.isArray(manifest.frozen_paths) ? manifest.frozen_paths : [];
  if (frozenPaths.some((pat) => globMatches(pat, relPath))) return true;
  const tasks = Array.isArray(manifest.tasks) ? manifest.tasks : [];
  for (const t of tasks) {
    if (Array.isArray(t.target_files) && t.target_files.some((pat) => globMatches(pat, relPath))) {
      return true;
    }
  }
  return false;
}

/**
 * Scan `missionsDir` and produce a compact, content-deduplicated mission bundle.
 * Identical file contents across missions (e.g. `lean-toolchain`, `lakefile.toml`,
 * shared specs, or LICENSE when frozen) are stored once in `blobs`.
 */
export function buildMissionsBundle(missionsDir) {
  const missionDirs = fs
    .readdirSync(missionsDir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && fs.existsSync(path.join(missionsDir, d.name, "sunstead.json")))
    .map((d) => d.name)
    .sort();

  const verifyPaths = missionDirs.map((dirName) => path.join(missionsDir, dirName, "verify"));
  const verifyContracts = extractVerifyContracts(verifyPaths);

  // Best known values for hill-climb tasks live outside the frozen per-mission
  // manifests (so updating a citation never changes a mission's spec hash or its
  // verifier image). They are merged into each task definition here; every
  // non-demo hill-climb task must have one (scripts/check-best-known.py checks the
  // sources in CI).
  const bestKnownPath = path.join(missionsDir, "best-known.json");
  const bestKnownRegistry = fs.existsSync(bestKnownPath)
    ? JSON.parse(fs.readFileSync(bestKnownPath, "utf8")).missions || {}
    : null;

  // Upstream dispute notices for tasks whose pinned upstream statement is known to
  // be false or misstated upstream live outside the frozen per-mission manifests
  // (so recording a dispute never changes a mission's spec_sha256 or verifier
  // container). Merged into task.upstream_disputed below.
  const taskDisputesPath = path.join(missionsDir, "task-disputes.json");
  const taskDisputesRegistry = fs.existsSync(taskDisputesPath)
    ? JSON.parse(fs.readFileSync(taskDisputesPath, "utf8")).missions || {}
    : {};

  const blobs = [];
  const blobIndex = new Map();
  let totalTasks = 0;
  let totalFileRefs = 0;
  let skippedFiles = 0;
  let skippedBytes = 0;
  let rawFileBytes = 0;

  const internBlob = (content) => {
    let idx = blobIndex.get(content);
    if (idx === undefined) {
      idx = blobs.length;
      blobs.push(content);
      blobIndex.set(content, idx);
    }
    return idx;
  };

  const missions = missionDirs.map((dirName) => {
    const fullDir = path.join(missionsDir, dirName);
    const manifest = JSON.parse(fs.readFileSync(path.join(fullDir, "sunstead.json"), "utf8"));
    if (manifest.mode === "hillclimb" && !manifest.demo) {
      if (!bestKnownRegistry) {
        throw new Error(
          `missions/best-known.json is required for non-demo hill-climb mission ${manifest.id}`
        );
      }
      const entries = bestKnownRegistry[manifest.id] || {};
      for (const task of manifest.tasks) {
        const bk = entries[task.id];
        if (!bk || !Number.isFinite(bk.value) || !bk.source || !bk.url) {
          throw new Error(
            `missions/best-known.json has no sourced best_known for hill-climb task ${manifest.id}/${task.id}`
          );
        }
        task.best_known = bk;
      }
    }
    const disputeEntries = taskDisputesRegistry[manifest.id] || {};
    for (const task of manifest.tasks) {
      const disp = disputeEntries[task.id];
      if (disp) {
        if (
          typeof disp.source !== "string" ||
          !disp.source.trim() ||
          typeof disp.reason !== "string" ||
          !disp.reason.trim() ||
          typeof disp.recorded_at !== "string" ||
          !disp.recorded_at.trim()
        ) {
          throw new Error(
            `missions/task-disputes.json has invalid dispute entry for ${manifest.id}/${task.id}`
          );
        }
        task.upstream_disputed = disp;
      }
    }
    const allFiles = walkFiles(fullDir).sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
    const frozenPaths = Array.isArray(manifest.frozen_paths) ? manifest.frozen_paths : [];
    const spec_sha256 = computeFilesSha256(
      allFiles.filter((f) => frozenPaths.some((pat) => globMatches(pat, f.rel)))
    );
    const seed_tree_sha256 = computeFilesSha256(allFiles);
    const verifier_kind = resolveVerifierKindForSync(dirName, manifest);
    totalTasks += Array.isArray(manifest.tasks) ? manifest.tasks.length : 0;

    const seed_file_refs = {};
    for (const f of allFiles) {
      if (!isWorkerServedSeedFile(f.rel, manifest)) {
        if (f.rel !== "verify" && f.rel !== "sunstead.json") {
          skippedFiles += 1;
          skippedBytes += fs.statSync(f.abs).size;
        }
        continue;
      }
      const content = fs.readFileSync(f.abs, "utf8");
      rawFileBytes += Buffer.byteLength(content, "utf8");
      totalFileRefs += 1;
      seed_file_refs[f.rel] = internBlob(content);
    }

    const verifyPath = path.join(fullDir, "verify");
    const verify_contract = verifyContracts[verifyPath] ?? null;

    return {
      manifest,
      spec_sha256,
      seed_tree_sha256,
      verifier_kind,
      seed_file_refs,
      ...(verify_contract ? { verify_contract } : {}),
    };
  });

  const knownTasksByMission = new Map(
    missions.map((m) => [m.manifest.id, new Set(m.manifest.tasks.map((t) => t.id))])
  );
  for (const [mid, entries] of Object.entries(taskDisputesRegistry)) {
    const taskIds = knownTasksByMission.get(mid);
    if (!taskIds) {
      throw new Error(`missions/task-disputes.json references unknown mission '${mid}'`);
    }
    for (const tid of Object.keys(entries || {})) {
      if (!taskIds.has(tid)) {
        throw new Error(`missions/task-disputes.json references unknown task '${mid}/${tid}'`);
      }
    }
  }

  const uniqueBlobBytes = blobs.reduce((n, b) => n + Buffer.byteLength(b, "utf8"), 0);
  return {
    missions,
    blobs,
    stats: {
      missionCount: missions.length,
      totalTasks,
      totalFileRefs,
      uniqueBlobs: blobs.length,
      dedupSavedBytes: Math.max(0, rawFileBytes - uniqueBlobBytes),
      skippedFiles,
      skippedBytes,
    },
  };
}

export function renderMissionsTs(bundle) {
  return (
    `// Auto-generated by scripts/sync-assets.mjs — do not edit manually.\n` +
    `import type { MissionManifest, MissionVerifyContract, VerifierKind } from "../core";\n\n` +
    `export interface SeedMission {\n` +
    `  manifest: MissionManifest;\n` +
    `  spec_sha256: string;\n` +
    `  seed_tree_sha256?: string;\n` +
    `  verifier_kind: VerifierKind;\n` +
    `  seed_files?: Record<string, string>;\n` +
    `  seed_file_refs?: Record<string, number>;\n` +
    `  verify_contract?: MissionVerifyContract;\n` +
    `}\n\n` +
    `export const SEED_FILE_BLOBS: readonly string[] = ${JSON.stringify(bundle.blobs)};\n\n` +
    `export const SEED_MISSIONS: SeedMission[] = ${JSON.stringify(bundle.missions)};\n\n` +
    `const hydratedCache = new WeakMap<object, Record<string, string>>();\n\n` +
    `/** Lazily materialize a mission's seed files from deduplicated SEED_FILE_BLOBS. */\n` +
    `export function getMissionSeedFiles(\n` +
    `  seed: Pick<SeedMission, "seed_files" | "seed_file_refs"> | null | undefined\n` +
    `): Record<string, string> {\n` +
    `  if (!seed) return {};\n` +
    `  if (seed.seed_files) return seed.seed_files;\n` +
    `  const refs = seed.seed_file_refs;\n` +
    `  if (!refs) return {};\n` +
    `  const cached = hydratedCache.get(seed);\n` +
    `  if (cached) return cached;\n` +
    `  const out: Record<string, string> = {};\n` +
    `  for (const [rel, idx] of Object.entries(refs)) {\n` +
    `    const blob = SEED_FILE_BLOBS[idx];\n` +
    `    if (typeof blob === "string") out[rel] = blob;\n` +
    `  }\n` +
    `  hydratedCache.set(seed, out);\n` +
    `  return out;\n` +
    `}\n`
  );
}

/**
 * Emit `static.ts` deduplicating shared HTML bodies (`index.html` is served at 2
 * routes and `what-is-this.html` at 4 routes) so they are bundled only once.
 */
export function renderStaticTs(webDir, repoRoot) {
  const indexHtml = fs.readFileSync(path.join(webDir, "index.html"), "utf8");
  const whatIsThisHtml = fs.readFileSync(path.join(webDir, "what-is-this.html"), "utf8");
  const stylesCss = fs.readFileSync(path.join(webDir, "styles.css"), "utf8");
  const proofsHtml = fs.readFileSync(path.join(webDir, "proofs.html"), "utf8");
  const appJs = fs.readFileSync(path.join(webDir, "app.js"), "utf8");
  const verifyPy = fs.readFileSync(path.join(repoRoot, "scripts", "sunstead_verify.py"), "utf8");

  return (
    `// Auto-generated by scripts/sync-assets.mjs — do not edit manually.\n` +
    `const INDEX_HTML = ${JSON.stringify(indexHtml)};\n` +
    `const WHAT_IS_THIS_HTML = ${JSON.stringify(whatIsThisHtml)};\n` +
    `const HTML_TYPE = "text/html; charset=utf-8";\n` +
    `export const STATIC_ASSETS: Record<string, { contentType: string; body: string }> = {\n` +
    `  "/": { contentType: HTML_TYPE, body: INDEX_HTML },\n` +
    `  "/index.html": { contentType: HTML_TYPE, body: INDEX_HTML },\n` +
    `  "/what-is-this": { contentType: HTML_TYPE, body: WHAT_IS_THIS_HTML },\n` +
    `  "/what-is-this/": { contentType: HTML_TYPE, body: WHAT_IS_THIS_HTML },\n` +
    `  "/what-is-this.html": { contentType: HTML_TYPE, body: WHAT_IS_THIS_HTML },\n` +
    `  "/about": { contentType: HTML_TYPE, body: WHAT_IS_THIS_HTML },\n` +
    `  "/styles.css": { contentType: "text/css; charset=utf-8", body: ${JSON.stringify(stylesCss)} },\n` +
    `  "/proofs.html": { contentType: HTML_TYPE, body: ${JSON.stringify(proofsHtml)} },\n` +
    `  "/app.js": { contentType: "application/javascript; charset=utf-8", body: ${JSON.stringify(appJs)} },\n` +
    `  "/verify.py": { contentType: "text/plain; charset=utf-8", body: ${JSON.stringify(verifyPy)} },\n` +
    `};\n`
  );
}

export function measureGeneratedBundle(missionsTs, staticTs) {
  const missionsRaw = Buffer.byteLength(missionsTs, "utf8");
  const staticRaw = Buffer.byteLength(staticTs, "utf8");
  const missionsGz = zlib.gzipSync(missionsTs, { level: 9 }).byteLength;
  const staticGz = zlib.gzipSync(staticTs, { level: 9 }).byteLength;
  const combinedGz = zlib.gzipSync(missionsTs + "\n" + staticTs, { level: 9 }).byteLength;
  return {
    missionsRaw,
    staticRaw,
    totalRaw: missionsRaw + staticRaw,
    missionsGz,
    staticGz,
    combinedGz,
  };
}

function formatKiB(bytes) {
  return `${(bytes / 1024).toFixed(1)} KiB`;
}

// Hash the exact generated mission module, including both seed files and merged
// best_known values. Write provenance separately so it never hashes itself.
function buildProvenance(repoRoot, missionsTs) {
  let git_sha = null;
  try {
    const sha = execFileSync("git", ["rev-parse", "--verify", "HEAD"], {
      cwd: repoRoot, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const changes = execFileSync("git", ["status", "--porcelain", "--untracked-files=normal"], {
      cwd: repoRoot, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    });
    // A dirty tree cannot be identified by its HEAD alone.
    if (/^[a-f0-9]{40}$/.test(sha) && !changes) git_sha = sha;
  } catch {
    // Source archives and local fixtures can still build, without a claim about their SHA.
  }
  return {
    git_sha,
    mission_bundle_sha256: crypto.createHash("sha256").update(missionsTs).digest("hex"),
  };
}

export function syncAssets({
  repoRoot = REPO_ROOT,
  genDir = GEN_DIR,
  maxGzBytes = Number(process.env.SUNSTEAD_MAX_ASSETS_GZ_BYTES || DEFAULT_MAX_ASSETS_GZ_BYTES),
  silent = false,
  requireCleanGit = false,
} = {}) {
  fs.mkdirSync(genDir, { recursive: true });
  const webDir = path.join(repoRoot, "web");
  const missionsDir = path.join(repoRoot, "missions");

  const staticTs = renderStaticTs(webDir, repoRoot);
  fs.writeFileSync(path.join(genDir, "static.ts"), staticTs);

  const bundle = buildMissionsBundle(missionsDir);
  const missionsTs = renderMissionsTs(bundle);
  const provenance = buildProvenance(repoRoot, missionsTs);
  if (requireCleanGit && !provenance.git_sha) {
    throw new Error("Deployment requires a clean Git checkout to record the deployed SHA.");
  }
  fs.writeFileSync(path.join(genDir, "missions.ts"), missionsTs);
  fs.writeFileSync(
    path.join(genDir, "provenance.ts"),
    "// Auto-generated by scripts/sync-assets.mjs — do not edit manually.\n" +
      "export const BUILD_PROVENANCE = " + JSON.stringify(provenance) + " as const;\n"
  );

  const sizes = measureGeneratedBundle(missionsTs, staticTs);
  if (Number.isFinite(maxGzBytes) && maxGzBytes > 0 && sizes.combinedGz > maxGzBytes) {
    throw new Error(
      `Generated Worker assets gzipped size (${formatKiB(sizes.combinedGz)}) exceeds budget (${formatKiB(maxGzBytes)})`
    );
  }
  if (!silent) {
    const s = bundle.stats;
    console.log(
      `Synced 10 static UI routes and ${s.missionCount} missions (${s.totalTasks} tasks) — ` +
        `missions.ts: ${formatKiB(sizes.missionsRaw)} raw / ${formatKiB(sizes.missionsGz)} gz, ` +
        `static.ts: ${formatKiB(sizes.staticRaw)} raw / ${formatKiB(sizes.staticGz)} gz, ` +
        `blobs: ${s.uniqueBlobs}/${s.totalFileRefs} unique (saved ${formatKiB(s.dedupSavedBytes)} dedup + ${formatKiB(s.skippedBytes)} unserved).`
    );
    if (sizes.combinedGz > WORKER_FREE_GZ_LIMIT_BYTES * 0.8) {
      console.warn(
        `[sync-assets] warning: combined generated assets (${formatKiB(sizes.combinedGz)} gz) approaching 3 MiB Free Worker limit (10 MiB Paid limit).`
      );
    }
  }
  return { bundle, sizes, provenance };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  syncAssets({ requireCleanGit: process.argv.includes("--require-clean-git") });
}
