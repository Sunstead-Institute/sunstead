# Local Sunstead Lean 4.35.0 repo-snapshot verifier image (e.g. LNSym, no Mathlib).
# Build context: the `missions/` directory (see scripts/build-verifiers.sh).
FROM debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV ELAN_HOME=/opt/elan
ENV PATH="/opt/elan/bin:${PATH}"

# elan installer pinned to a release tag; Lean toolchain pinned to v4.35.0.
RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/v4.0.0/elan-init.sh \
    | sh -s -- -y --default-toolchain leanprover/lean4:v4.35.0 --no-modify-path \
    && elan toolchain install leanprover/lean4:v4.35.0 \
    && lean --version \
    && lake --version \
    && chmod -R a-w,a+rX /opt/elan

# Trusted harness + native v4.35.0 kernel-replay checker, read-only to everyone but root.
COPY verifier-common/sunstead_sandbox.py verifier-common/SunsteadCheck.lean verifier-common/prebuild_snapshot.py /opt/sunstead/
RUN SYSROOT="$(lean --print-prefix)" \
    && mkdir -p /tmp/scbuild \
    && lean -c /tmp/scbuild/SunsteadCheck.c /opt/sunstead/SunsteadCheck.lean \
    && leanc -O2 -o /opt/sunstead/sunstead-check /tmp/scbuild/SunsteadCheck.c \
       -lleanshared -Wl,-rpath,"${SYSROOT}/lib/lean" \
    && rm -rf /tmp/scbuild \
    && /opt/sunstead/sunstead-check selftest | grep -q '"selftest":"ok"' \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10002 sunstead-runner \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10003 sunstead-checker \
    && mkdir -p /work

# Prebuild pinned upstream repo-snapshot `.olean` caches for bundled v4.35.0 missions.
COPY lnsym-aes-gcm-armv8 /tmp/prebuild-snapshots/lnsym-aes-gcm-armv8
RUN python3 /opt/sunstead/prebuild_snapshot.py /tmp/prebuild-snapshots/* \
    && rm -rf /tmp/prebuild-snapshots \
    && chmod -R a-w,a+rX /opt/sunstead

WORKDIR /work
