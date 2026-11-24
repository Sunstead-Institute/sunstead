FROM --platform=linux/amd64 debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e

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

COPY missions/tier1-metacomplexity-dag /missions/tier1-metacomplexity-dag
COPY missions/tier1-crypto-algebra-dag /missions/tier1-crypto-algebra-dag
COPY missions/tier2-soundness-bound /missions/tier2-soundness-bound
COPY missions/tier2-coding-bounds /missions/tier2-coding-bounds
COPY missions/verifier-common/sunstead_sandbox.py missions/verifier-common/SunsteadCheck.lean /opt/sunstead/
COPY cloudflare/containers/verifier_server.py /opt/verifier_server.py

# Seeds, harness and server are read-only. The server runs as root and never
# executes contributor code itself: `verify` drops to `sunstead-runner` for
# that, and the trusted kernel replay runs as `sunstead-checker`.
RUN chmod -R a-w,a+rX /missions /opt/sunstead /opt/verifier_server.py \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10002 sunstead-runner \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10003 sunstead-checker \
    && mkdir -p /work && chmod 0755 /work \
    && cd /tmp && lean --run /opt/sunstead/SunsteadCheck.lean selftest | grep -q '"selftest":"ok"'

WORKDIR /work
EXPOSE 8080
CMD ["python3", "/opt/verifier_server.py"]
