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
  imageFromApplications,
  verifierInputsHash,
} from "../scripts/deploy.mjs";

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
