# Local Sunstead Verus verifier image. Build context: the `missions/` directory
# (see scripts/build-verifiers.sh). Verus ships x86-64 Linux binaries only.
FROM --platform=linux/amd64 rust:1.91-slim-trixie@sha256:f75071363e7f4771769d4cf81b1b7b290e607f4d4459e8731f6abdcee9982dc8

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

# Verus release, pinned by version and checksum, plus the Rust toolchain that
# release requires (Verus refuses to run with any other). Verus release
# binaries need glibc >= 2.39, hence the trixie base.
ARG VERUS_VERSION=0.2026.11.22.1ce6a59
ARG VERUS_SHA256=c955d5958877f4f907cce80aa996d4239a481984829d82e325938c7bf242b0db
ARG VERUS_RUST_TOOLCHAIN=1.100.0-x86_64-unknown-linux-gnu
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

# Trusted harness, read-only to everyone but root.
COPY verifier-common/sunstead_sandbox.py /opt/sunstead/sunstead_sandbox.py
RUN chmod -R a-w,a+rX /opt/sunstead \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10002 sunstead-runner \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10003 sunstead-checker \
    && mkdir -p /work \
    && printf 'use vstd::prelude::*;\nverus! {\nproof fn selftest(x: u8) ensures x < 256 {}\n}\n' > /tmp/selftest.rs \
    && verus /tmp/selftest.rs --crate-type=lib \
    && rm /tmp/selftest.rs

# The container starts as root (the runner passes --user=0:0 and only
# CAP_SETUID/CAP_SETGID); `verify` drops to sunstead-runner for Verus.
WORKDIR /work
