import { bindings, defineConfig, defineContainer, defineWorker, exports } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

// Worker-only deploys (`npm run deploy:worker`) set SUNSTEAD_VERIFIER_IMAGE
// (and SUNSTEAD_VERIFIER_V435_IMAGE) to the digest-pinned images already
// running, so `cf deploy` skips Docker builds. Unset (the default, and always
// for `npm run deploy`), each image is rebuilt from its Dockerfile. Only a
// registry.cloudflare.com image pinned by sha256 digest is accepted: a mutable
// tag could swap the verifier silently.
const VERIFIER_IMAGE_RE = /^registry\.cloudflare\.com\/[A-Za-z0-9._\/-]+@sha256:[0-9a-f]{64}$/;
const procEnv = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env;

function readPinnedImage(envName: string): string | undefined {
  const val = procEnv?.[envName]?.trim();
  if (val && !VERIFIER_IMAGE_RE.test(val)) {
    throw new Error(
      `${envName} must be registry.cloudflare.com/...@sha256:<64 hex>, got ${JSON.stringify(val)}`,
    );
  }
  return val || undefined;
}

const prebuiltVerifierImage = readPinnedImage("SUNSTEAD_VERIFIER_IMAGE");
const prebuiltVerifierV435Image = readPinnedImage("SUNSTEAD_VERIFIER_V435_IMAGE");

const DO_CODE_UPDATE_MAX_DELAY_SEC = 15;

const lean4Container = defineContainer({
  name: "sunstead-verifier-lean4",
  image: prebuiltVerifierImage
    ? { reference: prebuiltVerifierImage }
    : {
        dockerfile: "./containers/lean4/Dockerfile",
        buildContext: "..",
      },
  instanceType: "standard-3", // 2 vCPU, 8 GiB RAM, 16 GB disk (Lean 4.36.0 + Mathlib v4.36.0)
  maxInstances: 6,
});

const lean4V435Container = defineContainer({
  name: "sunstead-verifier-lean4-v435",
  image: prebuiltVerifierV435Image
    ? { reference: prebuiltVerifierV435Image }
    : {
        dockerfile: "./containers/lean4-v4.35.0/Dockerfile",
        buildContext: "..",
      },
  instanceType: "standard-2", // 1 vCPU, 6 GiB RAM, 12 GB disk (Lean 4.35.0 repo-snapshot, no Mathlib)
  maxInstances: 4,
});

const worker = defineWorker({
  name: "sunstead",
  compatibilityDate: "2026-11-24",
  compatibilityFlags: ["nodejs_compat"],
  entrypoint,
  workersDev: true,
  // Durable Object code updates. Cloudflare's default ("deferred", 300 s) keeps an
  // active object on the old code until it hibernates. SunsteadHub never hibernates
  // while browsers hold /api/events open, so every deploy used to wait the full
  // 5 minutes. 15 s lets in-flight claims finish; a verification still running then
  // is cut off and the contributor gets a 5xx and resubmits (nothing is written until
  // the verdict arrives). See docs/DEPLOYMENT.md "Durable Object code updates".
  unsafe: {
    metadata: {
      code_update_strategy: { mode: "deferred", max_delay: DO_CODE_UPDATE_MAX_DELAY_SEC },
    },
  },
  domains: ["sunstead.org", "www.sunstead.org"],
  exports: {
    SunsteadHub: exports.durableObject({ storage: "sqlite" }),
    Lean4Verifier: exports.durableObject({ storage: "sqlite", container: lean4Container }),
    Lean4V435Verifier: exports.durableObject({ storage: "sqlite", container: lean4V435Container }),
  },
  env: {
    HUB: bindings.durableObject({ worker: "sunstead", exportName: "SunsteadHub" }),
    LEAN4_VERIFIER: bindings.durableObject({ worker: "sunstead", exportName: "Lean4Verifier" }),
    LEAN4_V435_VERIFIER: bindings.durableObject({ worker: "sunstead", exportName: "Lean4V435Verifier" }),
  },
});

export default defineConfig({
  worker,
  containers: [lean4Container, lean4V435Container],
});
