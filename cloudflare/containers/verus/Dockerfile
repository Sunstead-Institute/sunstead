FROM --platform=linux/amd64 rust:1.91-slim-bookworm@sha256:8514999d4786ef12efe89239e86b3d0a021b94b9d35108c8efe6c79ca7dc1a65

RUN apt-get update \
    && apt-get install -y --no-install-recommends git python3 ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

# Verus release, pinned by version and checksum, plus the Rust toolchain that
# release requires (Verus refuses to run with any other).
ARG VERUS_VERSION=PIN_ME
ARG VERUS_SHA256=PIN_ME
ARG VERUS_RUST_TOOLCHAIN=PIN_ME
RUN curl -fsSL -o /tmp/verus.zip \
        "https://github.com/verus-lang/verus/releases/download/release%2F${VERUS_VERSION}/verus-${VERUS_VERSION}-x86-linux.zip" \
    && echo "${VERUS_SHA256}  /tmp/verus.zip" | sha256sum -c - \
    && unzip -q /tmp/verus.zip -d /tmp/verus \
    && mv /tmp/verus/verus-x86-linux /opt/verus \
    && rm -rf /tmp/verus /tmp/verus.zip \
    && rustup toolchain install "${VERUS_RUST_TOOLCHAIN}" --profile minimal \
    && chmod -R a-w,a+rX /opt/verus \
    && chmod -R a+rX /usr/local/cargo /usr/local/rustup
ENV PATH="/opt/verus:${PATH}"

COPY missions/tier3-base16ct-verus /missions/tier3-base16ct-verus
COPY missions/verifier-common/sunstead_sandbox.py /opt/sunstead/sunstead_sandbox.py
COPY cloudflare/containers/verifier_server.py /opt/verifier_server.py

# Seeds, harness and server are read-only. The server runs as root and never
# executes contributor code itself: `verify` drops to `sunstead-runner` for Verus.
RUN chmod -R a-w,a+rX /missions /opt/sunstead /opt/verifier_server.py \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10002 sunstead-runner \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10003 sunstead-checker \
    && mkdir -p /work && chmod 0755 /work \
    && printf 'use vstd::prelude::*;\nverus! {\nproof fn selftest(x: u8) ensures x < 256 {}\n}\n' > /tmp/selftest.rs \
    && verus /tmp/selftest.rs --crate-type=lib \
    && rm /tmp/selftest.rs

WORKDIR /work
EXPOSE 8080
CMD ["python3", "/opt/verifier_server.py"]
