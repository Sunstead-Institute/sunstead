import { bindings, defineConfig, defineContainer, defineWorker, exports } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

const lean4Container = defineContainer({
  name: "sunstead-verifier-lean4",
  image: {
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
