FROM --platform=linux/amd64 debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e

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

COPY missions/arklib-near-capacity-primes /missions/arklib-near-capacity-primes
COPY missions/ieantn-chebyshev-kernel /missions/ieantn-chebyshev-kernel
COPY missions/ieantn-chebyshev-pipeline /missions/ieantn-chebyshev-pipeline
COPY missions/ieantn-schoenfeld-chebyshev /missions/ieantn-schoenfeld-chebyshev
COPY missions/ieantn-short-interval-primes /missions/ieantn-short-interval-primes
COPY missions/ieantn-zeta-foundations /missions/ieantn-zeta-foundations
COPY missions/ieantn-zero-free-regions /missions/ieantn-zero-free-regions
COPY missions/ieantn-zeta-logderiv-values /missions/ieantn-zeta-logderiv-values
COPY missions/ieantn-buthe-prime-bounds /missions/ieantn-buthe-prime-bounds
COPY missions/ieantn-buthe-partial-rh /missions/ieantn-buthe-partial-rh
COPY missions/ieantn-explicit-pnt-applications /missions/ieantn-explicit-pnt-applications
COPY missions/pnt-analytic-foundations /missions/pnt-analytic-foundations
COPY missions/matrix-rank444-f2 /missions/matrix-rank444-f2
COPY missions/matrix-rank-alphatensor-f2 /missions/matrix-rank-alphatensor-f2
COPY missions/aes-sbox-circuit /missions/aes-sbox-circuit
COPY missions/crypto-sbox-circuits /missions/crypto-sbox-circuits
COPY missions/crypto-linear-xor-opt /missions/crypto-linear-xor-opt
COPY missions/sorting-networks-opt /missions/sorting-networks-opt
COPY missions/sorting-networks-depth-opt /missions/sorting-networks-depth-opt
COPY missions/flt-standalone-foundations /missions/flt-standalone-foundations
COPY missions/fate-x-ideal-theory /missions/fate-x-ideal-theory
COPY missions/fate-x-dimension-and-geometry /missions/fate-x-dimension-and-geometry
COPY missions/fate-x-fields-rings-groups /missions/fate-x-fields-rings-groups
COPY missions/fate-h-fields-and-groups /missions/fate-h-fields-and-groups
COPY missions/verina-algorithms-pure-lean /missions/verina-algorithms-pure-lean
COPY missions/fc-solved-number-theory /missions/fc-solved-number-theory
COPY missions/fc-solved-combinatorics /missions/fc-solved-combinatorics
COPY missions/fc-solved-algebra-analysis /missions/fc-solved-algebra-analysis
COPY missions/fc-open-erdos-number-theory /missions/fc-open-erdos-number-theory
COPY missions/fc-open-erdos-combinatorics /missions/fc-open-erdos-combinatorics
COPY missions/fc-open-oeis-classics /missions/fc-open-oeis-classics
COPY missions/coding-theory-bounds /missions/coding-theory-bounds
COPY missions/extremal-graph-bounds /missions/extremal-graph-bounds
COPY missions/combinatorial-additive-opt /missions/combinatorial-additive-opt
COPY missions/combinatorial-designs-opt /missions/combinatorial-designs-opt
COPY missions/selection-networks-opt /missions/selection-networks-opt
COPY missions/matrix-rank-f2-extended /missions/matrix-rank-f2-extended
COPY missions/crypto-addition-chains /missions/crypto-addition-chains
COPY missions/crypto-zk-addition-chains /missions/crypto-zk-addition-chains
COPY missions/crypto-lwc-sboxes /missions/crypto-lwc-sboxes
COPY missions/crypto-std-sboxes /missions/crypto-std-sboxes
COPY missions/crypto-lwc-linear-xor /missions/crypto-lwc-linear-xor
COPY missions/sphere-packing-e8-foundations /missions/sphere-packing-e8-foundations
COPY missions/verifier-common/sunstead_sandbox.py missions/verifier-common/SunsteadCheck.lean missions/verifier-common/prebuild_cache.py missions/verifier-common/prebuild_snapshot.py /opt/sunstead/
COPY cloudflare/containers/verifier_server.py /opt/verifier_server.py

# Seeds, harness, native checker, prebuilt frozen `.olean` cache, and server
# are read-only. The server runs as root and never executes contributor code
# itself: `verify` drops to `sunstead-runner` for that, and the trusted kernel
# replay runs as `sunstead-checker`.
RUN SYSROOT="$(lean --print-prefix)" \
    && mkdir -p /tmp/scbuild \
    && lean -c /tmp/scbuild/SunsteadCheck.c /opt/sunstead/SunsteadCheck.lean \
    && leanc -O2 -o /opt/sunstead/sunstead-check /tmp/scbuild/SunsteadCheck.c \
       -lleanshared -Wl,-rpath,"${SYSROOT}/lib/lean" \
    && rm -rf /tmp/scbuild \
    && /opt/sunstead/sunstead-check selftest | grep -q '"selftest":"ok"' \
    && python3 /opt/sunstead/prebuild_cache.py /missions/* \
    && python3 /opt/sunstead/prebuild_snapshot.py /missions/* \
    && chmod -R a-w,a+rX /missions /opt/sunstead /opt/verifier_server.py \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10002 sunstead-runner \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10003 sunstead-checker \
    && mkdir -p /work && chmod 0755 /work

WORKDIR /work
EXPOSE 8080
CMD ["python3", "/opt/verifier_server.py"]
