// Tests for scripts/deploy.mjs (Worker-only vs full deploy helper).
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  IMAGE_RE,
  VERIFIER_APPS,
  buildCfDeployArgs,
  dockerfileInputs,
  findApplication,
  imageFromApplicationDetail,
  imageFromApplications,
  verifierInputsHash,
} from "../scripts/deploy.mjs";
import {
  REPO_ROOT,
  WORKER_FREE_GZ_LIMIT_BYTES,
  WORKER_PAID_GZ_LIMIT_BYTES,
  buildMissionsBundle,
  isWorkerServedSeedFile,
  measureGeneratedBundle,
  renderMissionsTs,
  renderStaticTs,
  syncAssets,
} from "../scripts/sync-assets.mjs";

const CF_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIGEST = "a".repeat(64);
const IMAGE = `registry.cloudflare.com/0adabb27c28d2e046f74e8af29c6b211/sunstead-verifier-lean4@sha256:${DIGEST}`;

test("dockerfileInputs lists the real verifier image's COPY sources", () => {
  const inputs = dockerfileInputs(fs.readFileSync(path.join(CF_ROOT, "containers/lean4/Dockerfile"), "utf8"));
  for (const expected of [
    "missions/pnt-analytic-foundations",
    "missions/verifier-common/sunstead_sandbox.py",
    "missions/verifier-common/SunsteadCheck.lean",
    "cloudflare/containers/verifier_server.py",
  ]) {
    assert.ok(inputs.includes(expected), `${expected} missing from ${inputs.join(", ")}`);
  }
});

test("dockerfileInputs handles flags, continuations and multi-stage copies", () => {
  const text = [
    "FROM x AS build",
    "COPY --chown=1000:1000 a/b \\",
    "     c.txt /dst/",
    "COPY --from=build /out /out",
    'ADD d /d',
  ].join("\n");
  assert.deepEqual(dockerfileInputs(text), ["a/b", "c.txt", "d"]);
});

test("verifierInputsHash changes when a copied mission file changes, not otherwise", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "sunstead-deploy-"));
  fs.mkdirSync(path.join(root, "missions/m"), { recursive: true });
  fs.mkdirSync(path.join(root, "web"), { recursive: true });
  const dockerfile = path.join(root, "Dockerfile");
  fs.writeFileSync(dockerfile, "FROM scratch\nCOPY missions/m /missions/m\n");
  fs.writeFileSync(path.join(root, "missions/m/Spec.lean"), "theorem t : True := sorry\n");
  fs.writeFileSync(path.join(root, "web/app.js"), "1");
  const before = verifierInputsHash(root, dockerfile);
  fs.writeFileSync(path.join(root, "web/app.js"), "2"); // UI-only edit
  assert.equal(verifierInputsHash(root, dockerfile), before);
  fs.writeFileSync(path.join(root, "missions/m/Spec.lean"), "theorem t : False := sorry\n");
  assert.notEqual(verifierInputsHash(root, dockerfile), before);
  fs.rmSync(root, { recursive: true, force: true });
});

test("the real verifier inputs hash is a stable sha256", () => {
  const h = verifierInputsHash();
  assert.match(h, /^[0-9a-f]{64}$/);
  assert.equal(verifierInputsHash(), h);
});

test("imageFromApplications finds the live digest in common output shapes", () => {
  const app = { name: "sunstead-verifier-lean4", configuration: { image: IMAGE } };
  assert.equal(imageFromApplications(JSON.stringify([app])), IMAGE);
  assert.equal(
    imageFromApplications("[info] Loaded profile\n" + JSON.stringify({ result: [{ name: "other" }, app] })),
    IMAGE
  );
  assert.throws(() => imageFromApplications(JSON.stringify([{ name: "other" }])), /no container application/);
});

test("imageFromApplications handles active container rollouts safely", () => {
  const nextDigest = "b".repeat(64);
  const nextImage = `registry.cloudflare.com/0adabb27c28d2e046f74e8af29c6b211/sunstead-verifier-lean4@sha256:${nextDigest}`;

  // When Cloudflare exposes target.configuration.image during a rollout, prefer it over the stale configuration.image.
  assert.equal(
    imageFromApplications(
      JSON.stringify([
        {
          name: "sunstead-verifier-lean4",
          active_rollout_id: "ec4844b6-f275-4604-b5bf-3f13145eb375",
          configuration: { image: IMAGE },
          target: { configuration: { image: nextImage } },
        },
      ])
    ),
    nextImage
  );

  // Also support rollout.target_configuration.image.
  assert.equal(
    imageFromApplications(
      JSON.stringify([
        {
          name: "sunstead-verifier-lean4",
          active_rollout_id: "ec4844b6-f275-4604-b5bf-3f13145eb375",
          configuration: { image: IMAGE },
          rollout: { target_configuration: { image: nextImage } },
        },
      ])
    ),
    nextImage
  );

  // When active_rollout_id is set without a target image, fail closed instead of pinning the stale pre-rollout digest.
  assert.throws(
    () =>
      imageFromApplications(
        JSON.stringify([
          {
            name: "sunstead-verifier-lean4",
            active_rollout_id: "ec4844b6-f275-4604-b5bf-3f13145eb375",
            configuration: { image: IMAGE },
          },
        ])
      ),
    /active container rollout.*SUNSTEAD_VERIFIER_IMAGE/
  );

  // Verify the v4.35.0 app reports its own env var name on fail-closed.
  const v435Img = IMAGE.replace("sunstead-verifier-lean4", "sunstead-verifier-lean4-v435");
  assert.throws(
    () =>
      imageFromApplications(
        JSON.stringify([
          {
            name: "sunstead-verifier-lean4-v435",
            active_rollout_id: "11111111-2222-3333-4444-555555555555",
            configuration: { image: v435Img },
          },
        ]),
        "sunstead-verifier-lean4-v435"
      ),
    /active container rollout.*SUNSTEAD_VERIFIER_V435_IMAGE/
  );
});

test("buildCfDeployArgs defaults to immediate rollout without duplicating caller flags", () => {
  assert.deepEqual(buildCfDeployArgs(["--dry-run"]), [
    "cf",
    "deploy",
    "--containers-rollout",
    "immediate",
    "--dry-run",
  ]);
  assert.deepEqual(buildCfDeployArgs(["--containers-rollout", "gradual"]), [
    "cf",
    "deploy",
    "--containers-rollout",
    "gradual",
  ]);
  assert.deepEqual(buildCfDeployArgs(["--containers-rollout=gradual", "--dry-run"]), [
    "cf",
    "deploy",
    "--containers-rollout=gradual",
    "--dry-run",
  ]);
});

test("IMAGE_RE accepts only digest-pinned Cloudflare registry images", () => {
  assert.ok(IMAGE_RE.test(IMAGE));
  assert.ok(!IMAGE_RE.test(IMAGE.replace(/@sha256:.*/, ":latest")));
  assert.ok(!IMAGE_RE.test(`docker.io/evil/img@sha256:${DIGEST}`));
  assert.ok(!IMAGE_RE.test(`${IMAGE} `));
});

test("cloudflare.config.ts and deploy.mjs use the same image pattern", () => {
  const config = fs.readFileSync(path.join(CF_ROOT, "cloudflare.config.ts"), "utf8");
  assert.ok(config.includes(`const VERIFIER_IMAGE_RE = ${IMAGE_RE.toString()};`));
});

test("cloudflare.config.ts caps the Durable Object code-update delay", () => {
  // Without this, open /api/events streams keep SunsteadHub from hibernating and
  // every deploy waits Cloudflare's 300 s default before the new hub code runs.
  const src = fs.readFileSync(path.join(CF_ROOT, "cloudflare.config.ts"), "utf8");
  assert.match(src, /code_update_strategy:\s*\{\s*mode:\s*"deferred",\s*max_delay:\s*DO_CODE_UPDATE_MAX_DELAY_SEC\s*\}/);
  const delay = Number(src.match(/const DO_CODE_UPDATE_MAX_DELAY_SEC = (\d+);/)?.[1]);
  assert.ok(delay > 0 && delay <= 60, `max_delay ${delay}s should be short`);
});

test("multi-toolchain deploy tracks v4.36.0, v4.35.0, and v4.31.0 verifier container inputs", () => {
  const names = VERIFIER_APPS.map((a) => a.name);
  assert.deepEqual(names, [
    "sunstead-verifier-lean4",
    "sunstead-verifier-lean4-v435",
    "sunstead-verifier-lean4-v431",
  ]);
  const v435Inputs = dockerfileInputs(
    fs.readFileSync(path.join(CF_ROOT, "containers/lean4-v4.35.0/Dockerfile"), "utf8")
  );
  for (const expected of [
    "missions/lnsym-aes-gcm-armv8",
    "missions/lnsym-gcm-gmult-armv8",
    "missions/verifier-common/sunstead_sandbox.py",
    "missions/verifier-common/SunsteadCheck.lean",
    "missions/verifier-common/prebuild_snapshot.py",
    "cloudflare/containers/verifier_server.py",
  ]) {
    assert.ok(v435Inputs.includes(expected), `${expected} missing from ${v435Inputs.join(", ")}`);
  }
  const v431Inputs = dockerfileInputs(
    fs.readFileSync(path.join(CF_ROOT, "containers/lean4-v4.31.0/Dockerfile"), "utf8")
  );
  for (const expected of [
    "missions/curve25519-dalek",
    "missions/verifier-common/sunstead_sandbox.py",
    "missions/verifier-common/SunsteadCheck.lean",
    "missions/verifier-common/prebuild_snapshot.py",
    "cloudflare/containers/verifier_server.py",
  ]) {
    assert.ok(v431Inputs.includes(expected), `${expected} missing from ${v431Inputs.join(", ")}`);
  }
  const v435Img = IMAGE.replace("sunstead-verifier-lean4", "sunstead-verifier-lean4-v435");
  const v431Img = IMAGE.replace("sunstead-verifier-lean4", "sunstead-verifier-lean4-v431");
  const listPayload = JSON.stringify([
    { name: "sunstead-verifier-lean4", configuration: { image: IMAGE } },
    { name: "sunstead-verifier-lean4-v435", configuration: { image: v435Img } },
    { name: "sunstead-verifier-lean4-v431", configuration: { image: v431Img } },
  ]);
  assert.equal(imageFromApplications(listPayload, "sunstead-verifier-lean4-v435"), v435Img);
  assert.equal(imageFromApplications(listPayload, "sunstead-verifier-lean4-v431"), v431Img);

  // Verify the v4.31.0 app reports its own env var name on active-rollout fail-closed.
  assert.throws(
    () =>
      imageFromApplications(
        JSON.stringify([
          {
            name: "sunstead-verifier-lean4-v431",
            active_rollout_id: "22222222-3333-4444-5555-666666666666",
            configuration: { image: v431Img },
          },
        ]),
        "sunstead-verifier-lean4-v431"
      ),
    /active container rollout.*SUNSTEAD_VERIFIER_V431_IMAGE/
  );
});

test("findApplication and imageFromApplicationDetail read authoritative single-app container state", () => {
  const v431New = IMAGE.replace("sunstead-verifier-lean4", "sunstead-verifier-lean4-v431").replace(
    DIGEST,
    "c".repeat(64)
  );
  const app = findApplication(
    JSON.stringify([
      {
        id: "a03319b6-dbe0-4f54-b965-2035d654ad0b",
        name: "sunstead-verifier-lean4-v431",
        active_rollout_id: "de3501c7-4844-4da7-ba38-c752776ef5ce",
        configuration: { image: IMAGE },
      },
    ]),
    "sunstead-verifier-lean4-v431"
  );
  assert.equal(app.id, "a03319b6-dbe0-4f54-b965-2035d654ad0b");

  assert.equal(
    imageFromApplicationDetail(
      JSON.stringify({
        id: app.id,
        name: "sunstead-verifier-lean4-v431",
        version: 6,
        configuration: { image: v431New },
      }),
      "sunstead-verifier-lean4-v431"
    ),
    v431New
  );
  assert.equal(
    imageFromApplicationDetail(
      JSON.stringify({
        result: {
          id: app.id,
          name: "sunstead-verifier-lean4-v431",
          version: 6,
          configuration: { image: v431New },
        },
      }),
      "sunstead-verifier-lean4-v431"
    ),
    v431New
  );
  assert.throws(
    () =>
      imageFromApplicationDetail(
        JSON.stringify({
          id: app.id,
          name: "sunstead-verifier-lean4-v431",
          active_rollout_id: "still-rolling",
          configuration: { image: v431New },
        }),
        "sunstead-verifier-lean4-v431"
      ),
    /active container rollout.*SUNSTEAD_VERIFIER_V431_IMAGE/
  );
});

test("sync-assets deduplicates shared blobs, preserves task-disputes.json, drops unserved files, and keeps real Worker bundle compact", () => {
  const bundle = buildMissionsBundle(path.join(REPO_ROOT, "missions"));
  const missionsTs = renderMissionsTs(bundle);
  const staticTs = renderStaticTs(path.join(REPO_ROOT, "web"), REPO_ROOT);
  const sizes = measureGeneratedBundle(missionsTs, staticTs);

  assert.ok(bundle.stats.missionCount >= 22);
  assert.ok(bundle.stats.uniqueBlobs < bundle.stats.totalFileRefs, "duplicate files across missions must be deduplicated");
  assert.ok(bundle.stats.dedupSavedBytes > 10_000, `expected >10 KiB dedup savings, got ${bundle.stats.dedupSavedBytes}`);
  assert.ok(bundle.stats.skippedBytes > 10_000, "unserved LICENSE copies outside frozen_paths must be excluded from Worker bundle");
  assert.ok(sizes.missionsGz < 1024 * 1024, `real missions.ts gz (${sizes.missionsGz}) should stay compact (<1 MiB)`);
  assert.ok(sizes.combinedGz < WORKER_FREE_GZ_LIMIT_BYTES, "real generated assets must fit comfortably within 3 MiB Free Worker limit");

  // Verify missions/task-disputes.json is merged into affected tasks without changing spec hashes.
  const butheMission = bundle.missions.find((m) => m.manifest.id === "ieantn-buthe-prime-bounds");
  const butheLemma3 = butheMission?.manifest.tasks.find((t) => t.id === "buthe_lemma_3_bounds");
  assert.ok(butheLemma3?.upstream_disputed, "ieantn-buthe-prime-bounds/buthe_lemma_3_bounds must carry upstream_disputed from task-disputes.json");

  // Verify static.ts deduplicates shared index.html and what-is-this.html bodies.
  assert.equal((staticTs.match(/const WHAT_IS_THIS_HTML = /g) || []).length, 1);
  assert.equal((staticTs.match(/const INDEX_HTML = /g) || []).length, 1);

  // Verify every target file is resolvable through SEED_FILE_BLOBS and verify/sunstead.json are omitted.
  for (const m of bundle.missions) {
    for (const t of m.manifest.tasks) {
      for (const tf of t.target_files) {
        const idx = m.seed_file_refs[tf];
        assert.equal(typeof idx, "number", `${m.manifest.id}: missing seed_file_refs entry for target ${tf}`);
        assert.equal(typeof bundle.blobs[idx], "string");
      }
    }
    assert.equal("verify" in m.seed_file_refs, false);
    assert.equal("sunstead.json" in m.seed_file_refs, false);
  }
});

test("isWorkerServedSeedFile keeps frozen_paths and target_files while dropping dead files", () => {
  const manifest = {
    frozen_paths: ["Pkg/Spec.lean", "UPSTREAM.json", "lakefile.toml", "lean-toolchain", "verify", "sunstead.json"],
    tasks: [{ id: "t1", target_files: ["Pkg/T1.lean"] }],
  };
  assert.equal(isWorkerServedSeedFile("Pkg/Spec.lean", manifest), true);
  assert.equal(isWorkerServedSeedFile("Pkg/T1.lean", manifest), true);
  assert.equal(isWorkerServedSeedFile("UPSTREAM.json", manifest), true);
  assert.equal(isWorkerServedSeedFile("verify", manifest), false);
  assert.equal(isWorkerServedSeedFile("sunstead.json", manifest), false);
  assert.equal(isWorkerServedSeedFile("LICENSE", manifest), false);
  assert.equal(isWorkerServedSeedFile("README.md", manifest), false);
});

test("sync-assets scales cleanly to 50 multi-task Arena Packs (1,000 tasks) well under Cloudflare Worker limits", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sunstead-scale-1k-"));
  try {
    const missionsDir = path.join(tmp, "missions");
    const webDir = path.join(tmp, "web");
    const scriptsDir = path.join(tmp, "scripts");
    fs.mkdirSync(missionsDir, { recursive: true });
    fs.mkdirSync(webDir, { recursive: true });
    fs.mkdirSync(scriptsDir, { recursive: true });
    for (const f of ["index.html", "what-is-this.html", "styles.css", "proofs.html", "app.js"]) {
      fs.writeFileSync(path.join(webDir, f), `/* ${f} */\n`);
    }
    fs.writeFileSync(path.join(scriptsDir, "sunstead_verify.py"), "# verify\n");

    const sharedLicense = "Apache License Version 2.0\n" + "Copyright Sunstead\n".repeat(400);
    const sharedToolchain = "leanprover/lean4:v4.36.0\n";

    // Create 50 Arena Packs × 20 tasks = 1,000 tasks.
    for (let m = 0; m < 50; m++) {
      const mid = `fc-arena-${String(m).padStart(2, "0")}`;
      const lib = `FcArena${m}`;
      const mdir = path.join(missionsDir, mid);
      const libDir = path.join(mdir, lib);
      fs.mkdirSync(libDir, { recursive: true });
      fs.writeFileSync(path.join(mdir, "LICENSE"), sharedLicense);
      fs.writeFileSync(path.join(mdir, "lean-toolchain"), sharedToolchain);
      fs.writeFileSync(
        path.join(mdir, "lakefile.toml"),
        `name = "${mid.replace(/-/g, "_")}"\nversion = "0.1.0"\n\n[[require]]\nname = "mathlib"\ngit = "https://github.com/leanprover-community/mathlib4.git"\nrev = "v4.36.0"\n\n[[lean_lib]]\nname = "${lib}"\n`
      );
      fs.writeFileSync(
        path.join(libDir, "Spec.lean"),
        `import Mathlib\nnamespace ${lib}\ndef sharedParam (n : Nat) : Nat := n + ${m}\nend ${lib}\n`
      );

      const tasks = [];
      const pyTasks = [];
      for (let t = 0; t < 20; t++) {
        const tid = `conjecture_${m}_${t}`;
        const rel = `${lib}/T${t}.lean`;
        fs.writeFileSync(
          path.join(mdir, rel),
          `import ${lib}.Spec\nnamespace ${lib}\ntheorem ${tid} (n : Nat) : sharedParam n ≥ ${m} := by\n  sorry\nend ${lib}\n`
        );
        tasks.push({
          id: tid,
          title: `Open conjecture ${m}.${t}`,
          target_files: [rel],
          depends_on: [],
          upstream_url: `https://github.com/google-deepmind/formal-conjectures/blob/${"a".repeat(40)}/FormalConjectures/P${m}_${t}.lean#L10-L15`,
        });
        pyTasks.push(
          `    "${tid}": {"module": "${lib}.T${t}", "theorem": "${lib}.${tid}", "statement": "def ${tid} : Prop := ∀ n : Nat, ${lib}.sharedParam n ≥ ${m}"},`
        );
      }

      fs.writeFileSync(
        path.join(mdir, "UPSTREAM.json"),
        JSON.stringify({ repo: "google-deepmind/formal-conjectures", commit: "a".repeat(40), license: "Apache-2.0", checks: [] })
      );
      fs.writeFileSync(
        path.join(mdir, "sunstead.json"),
        JSON.stringify({
          id: mid,
          title: `Arena ${m}`,
          tier: 1,
          mode: "dag",
          open_conjecture: true,
          frozen_paths: [`${lib}/Spec.lean`, "UPSTREAM.json", "lakefile.toml", "lean-toolchain", "verify", "sunstead.json"],
          verifier: { image: "sunstead/verifier-lean4:v0.2", command: ["./verify"] },
          tasks,
        })
      );
      fs.writeFileSync(
        path.join(mdir, "verify"),
        `LIB_ROOT = "${lib}"\nFROZEN_FILES = ["${lib}/Spec.lean"]\nSTATEMENT_PREAMBLE = ""\nTASKS = {\n${pyTasks.join("\n")}\n}\n`
      );
    }

    const genDir = path.join(tmp, "generated");
    const { bundle, sizes } = syncAssets({ repoRoot: tmp, genDir, silent: true });
    assert.equal(bundle.stats.missionCount, 50);
    assert.equal(bundle.stats.totalTasks, 1000);
    assert.equal(bundle.stats.skippedFiles, 50, "50 unserved LICENSE files skipped");
    assert.ok(sizes.combinedGz < WORKER_FREE_GZ_LIMIT_BYTES, `1,000-task bundle (${sizes.combinedGz} gz) must fit inside 3 MiB Free limit`);
    assert.ok(sizes.combinedGz < WORKER_PAID_GZ_LIMIT_BYTES);

    // Budget guard fails closed when maxGzBytes is exceeded.
    assert.throws(
      () => syncAssets({ repoRoot: tmp, genDir, maxGzBytes: 1024, silent: true }),
      /exceeds budget/
    );

    // Unknown task in task-disputes.json fails closed.
    fs.writeFileSync(
      path.join(missionsDir, "task-disputes.json"),
      JSON.stringify({
        missions: {
          "fc-arena-00": {
            nonexistent_task: { source: "upstream", reason: "bad", recorded_at: "2026-11-26" },
          },
        },
      })
    );
    assert.throws(() => buildMissionsBundle(missionsDir), /unknown task 'fc-arena-00\/nonexistent_task'/);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
