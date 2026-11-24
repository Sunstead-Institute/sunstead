# Local Sunstead Lean 4 verifier image. Build context: the `missions/` directory
# (see scripts/build-verifiers.sh).
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV ELAN_HOME=/opt/elan
ENV PATH="/opt/elan/bin:${PATH}"

# TODO(pin): pin elan-init.sh to a release tag + checksum instead of master.
RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
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
