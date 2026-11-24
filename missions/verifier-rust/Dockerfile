# Local Sunstead Rust verifier image. Build context: the `missions/` directory
# (see scripts/build-verifiers.sh).
FROM rust:1.91-slim-bookworm@sha256:8514999d4786ef12efe89239e86b3d0a021b94b9d35108c8efe6c79ca7dc1a65

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Trusted harness, read-only to everyone but root.
COPY verifier-common/sunstead_sandbox.py /opt/sunstead/sunstead_sandbox.py
RUN chmod -R a-w,a+rX /opt/sunstead \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10002 sunstead-runner \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10003 sunstead-checker \
    && chmod -R a+rX /usr/local/cargo /usr/local/rustup \
    && mkdir -p /work

# The container starts as root (the hub passes --user=0:0 and only
# CAP_SETUID/CAP_SETGID); `verify` drops to sunstead-runner for contributor code.
WORKDIR /work
