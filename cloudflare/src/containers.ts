import { Container } from "@cloudflare/containers";

/**
 * Hermetic Lean 4.36.0 + Mathlib v4.36.0 verification container running with outbound internet disabled.
 */
export class Lean4Verifier extends Container {
  defaultPort = 8080;
  sleepAfter = "3m";
  enableInternet = false;
}
