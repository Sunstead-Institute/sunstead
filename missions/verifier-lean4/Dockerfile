# Local Sunstead Lean 4.36.0 + Mathlib verifier image.
# Build context: the `missions/` directory (see scripts/build-verifiers.sh).
FROM debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV ELAN_HOME=/opt/elan
ENV PATH="/opt/elan/bin:${PATH}"

# elan installer pinned to a release tag; Lean toolchain pinned to v4.36.0.
RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/v4.0.0/elan-init.sh \
    | sh -s -- -y --default-toolchain leanprover/lean4:v4.36.0 --no-modify-path \
    && elan toolchain install leanprover/lean4:v4.36.0 \
    && lean --version \
    && lake --version \
    && chmod -R a-w,a+rX /opt/elan

# Pre-fetch Mathlib v4.36.0 oleans read-only at /opt/mathlib for offline verification.
RUN mkdir -p /opt/mathlib \
    && cd /opt/mathlib \
    && printf 'leanprover/lean4:v4.36.0\n' > lean-toolchain \
    && printf 'name = "SunsteadMathlib"\nversion = "0.1.0"\n\n[[require]]\nname = "mathlib"\ngit = "https://github.com/leanprover-community/mathlib4.git"\nrev = "v4.36.0"\n' > lakefile.toml \
    && lake update mathlib \
    && rm -rf /root/.cache /opt/mathlib/.lake/packages/*/.git \
    && find /opt/mathlib/.lake/packages -type f \( \
         -name "*.c" -o -name "*.c.o" -o -name "*.c.o.export" -o -name "*.c.o.noexport" \
         -o -name "*.ilean" -o -name "*.ilean.hash" \
       \) -delete \
    && chmod -R a-w,a+rX /opt/mathlib

# Trusted harness + native kernel-replay checker, read-only to everyone but root.
COPY verifier-common/sunstead_sandbox.py verifier-common/SunsteadCheck.lean verifier-common/prebuild_cache.py verifier-common/prebuild_snapshot.py /opt/sunstead/
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

# Prebuild SHA-256-keyed read-only frozen `.olean` caches for bundled missions.
COPY arklib-near-capacity-primes /tmp/prebuild-missions/arklib-near-capacity-primes
COPY pnt-analytic-foundations /tmp/prebuild-missions/pnt-analytic-foundations
COPY matrix-rank444-f2 /tmp/prebuild-missions/matrix-rank444-f2
COPY onboarding-sandbox /tmp/prebuild-missions/onboarding-sandbox
RUN python3 /opt/sunstead/prebuild_cache.py /tmp/prebuild-missions/* \
    && rm -rf /tmp/prebuild-missions \
    && chmod -R a-w,a+rX /opt/sunstead

WORKDIR /work
