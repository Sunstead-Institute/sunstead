# Local Sunstead Lean 4 verifier image. Build context: the `missions/` directory
# (see scripts/build-verifiers.sh).
FROM debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV ELAN_HOME=/opt/elan
ENV PATH="/opt/elan/bin:${PATH}"

# elan installer pinned to a release tag; the Lean toolchain is pinned by version.
RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/v4.0.0/elan-init.sh \
    | sh -s -- -y --default-toolchain leanprover/lean4:v4.14.0 --no-modify-path \
    && elan toolchain install leanprover/lean4:v4.14.0 \
    && lean --version \
    && lake --version \
    && chmod -R a-w,a+rX /opt/elan

# Trusted harness + kernel-replay checker, read-only to everyone but root.
COPY verifier-common/sunstead_sandbox.py verifier-common/SunsteadCheck.lean /opt/sunstead/
RUN chmod -R a-w,a+rX /opt/sunstead \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10002 sunstead-runner \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10003 sunstead-checker \
    && mkdir -p /work \
    && cd /tmp && lean --run /opt/sunstead/SunsteadCheck.lean selftest | grep -q '"selftest":"ok"'

WORKDIR /work
