import { bindings, defineConfig, defineContainer, defineWorker, exports } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

const lean4Container = defineContainer({
  name: "sunstead-verifier-lean4",
  image: {
    dockerfile: "./containers/lean4/Dockerfile",
    buildContext: "..",
  },
  instanceType: "standard-1", // 1/2 vCPU, 4 GiB RAM, 8 GB disk
  maxInstances: 4,
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
    // Tombstones retiring the v0.2 Rust/Verus verifier DO namespaces on the
    // first Lean-only v1 deploy. Safe to delete once `cf deploy` reports them
    // as stale_tombstone (see docs/DEPLOYMENT.md).
    RustVerifier: exports.durableObject({ state: "deleted" }),
    VerusVerifier: exports.durableObject({ state: "deleted" }),
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
