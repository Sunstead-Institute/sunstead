import { Container } from "@cloudflare/containers";

/**
 * Hermetic Lean 4.14.0 verification container running with outbound internet disabled.
 */
export class Lean4Verifier extends Container {
  defaultPort = 8080;
  sleepAfter = "3m";
  enableInternet = false;
}

/**
 * Hermetic Rust ML-DSA verification container running with outbound internet disabled.
 */
export class RustVerifier extends Container {
  defaultPort = 8080;
  sleepAfter = "3m";
  enableInternet = false;
}
