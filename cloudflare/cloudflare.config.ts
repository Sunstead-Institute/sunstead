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

const rustContainer = defineContainer({
  name: "sunstead-verifier-rust",
  image: {
    dockerfile: "./containers/rust/Dockerfile",
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
  // Once sunstead.org transfers to Cloudflare DNS, uncomment:
  // domains: ["sunstead.org"],
  exports: {
    SunsteadHub: exports.durableObject({ storage: "sqlite" }),
    Lean4Verifier: exports.durableObject({ storage: "sqlite", container: lean4Container }),
    RustVerifier: exports.durableObject({ storage: "sqlite", container: rustContainer }),
  },
  env: {
    HUB: bindings.durableObject({ worker: "sunstead", exportName: "SunsteadHub" }),
    LEAN4_VERIFIER: bindings.durableObject({ worker: "sunstead", exportName: "Lean4Verifier" }),
    RUST_VERIFIER: bindings.durableObject({ worker: "sunstead", exportName: "RustVerifier" }),
  },
});

export default defineConfig({
  worker,
  containers: [lean4Container, rustContainer],
});
