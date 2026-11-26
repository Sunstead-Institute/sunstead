import { Container } from "@cloudflare/containers";

/**
 * Hermetic Lean 4.36.0 + Mathlib v4.36.0 verification container running with outbound internet disabled.
 */
export class Lean4Verifier extends Container {
  defaultPort = 8080;
  // Keep in step with VERIFIER_WARM_MS in core.ts.
  sleepAfter = "10m";
  enableInternet = false;
}

/**
 * Hermetic Lean 4.35.0 repo-snapshot verification container (e.g. LNSym) with outbound internet disabled.
 */
export class Lean4V435Verifier extends Container {
  defaultPort = 8080;
  // Keep in step with VERIFIER_WARM_MS in core.ts.
  sleepAfter = "10m";
  enableInternet = false;
}

/**
 * Hermetic Lean 4.31.0 + Mathlib + Aeneas repo-snapshot verification container (e.g. curve25519-dalek)
 * running with outbound internet disabled.
 */
export class Lean4V431Verifier extends Container {
  defaultPort = 8080;
  // Keep in step with VERIFIER_WARM_MS in core.ts.
  sleepAfter = "10m";
  enableInternet = false;
}
