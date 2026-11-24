# Vendored upstream source

`base16ct-1.0.0/` is the RustCrypto `base16ct` crate, version 1.0.0, unpacked
from crates.io (`src/`, `Cargo.toml` and the licenses only).

    https://static.crates.io/crates/base16ct/base16ct-1.0.0.crate
    sha256 fd307490d624467aa6f74b0eabb77633d1f758a7b25f12bceb0b22e08d9726f6
    (matches the `cksum` in the crates.io index)

`scripts/check-upstream.py` re-downloads the crate and checks these files are
unchanged. The verifier checks, on every submission, that each executable
function in `statements/` is token-for-token the function of the same name here.
