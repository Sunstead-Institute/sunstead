# Local Sunstead Rust verifier image. Build context: the `missions/` directory
# (see scripts/build-verifiers.sh).
FROM rust:slim-bookworm

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
