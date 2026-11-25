import { bindings, defineConfig, defineContainer, defineWorker, exports } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

// Worker-only deploys (`npm run deploy:worker`) set SUNSTEAD_VERIFIER_IMAGE to the
// digest-pinned image already running, so `cf deploy` skips the Docker build.
// Unset (the default, and always for `npm run deploy`), the image is rebuilt
// from the Dockerfile. Only a registry.cloudflare.com image pinned by sha256
// digest is accepted: a mutable tag could swap the verifier silently.
const VERIFIER_IMAGE_RE = /^registry\.cloudflare\.com\/[A-Za-z0-9._\/-]+@sha256:[0-9a-f]{64}$/;
const prebuiltVerifierImage = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process
  ?.env?.SUNSTEAD_VERIFIER_IMAGE?.trim();
if (prebuiltVerifierImage && !VERIFIER_IMAGE_RE.test(prebuiltVerifierImage)) {
  throw new Error(
    `SUNSTEAD_VERIFIER_IMAGE must be registry.cloudflare.com/...@sha256:<64 hex>, got ${JSON.stringify(prebuiltVerifierImage)}`,
  );
}

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

const worker = defineWorker({
  name: "sunstead",
  compatibilityDate: "2026-11-24",
  compatibilityFlags: ["nodejs_compat"],
  entrypoint,
  workersDev: true,
  domains: ["sunstead.org", "www.sunstead.org"],
  exports: {
    SunsteadHub: exports.durableObject({ storage: "sqlite" }),
    Lean4Verifier: exports.durableObject({ storage: "sqlite", container: lean4Container }),
  },
  env: {
    HUB: bindings.durableObject({ worker: "sunstead", exportName: "SunsteadHub" }),
    LEAN4_VERIFIER: bindings.durableObject({ worker: "sunstead", exportName: "Lean4Verifier" }),
  },
});

export default defineConfig({
  worker,
  containers: [lean4Container],
});
