FROM --platform=linux/amd64 debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV ELAN_HOME=/opt/elan
ENV PATH="/opt/elan/bin:${PATH}"

RUN curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
    | sh -s -- -y --default-toolchain leanprover/lean4:v4.14.0 --no-modify-path \
    && elan toolchain install leanprover/lean4:v4.14.0 \
    && lean --version \
    && lake --version \
    && chmod -R a+rX /opt/elan

COPY missions/tier1-metacomplexity-dag /missions/tier1-metacomplexity-dag
COPY missions/tier1-crypto-algebra-dag /missions/tier1-crypto-algebra-dag
COPY missions/tier2-soundness-bound /missions/tier2-soundness-bound
COPY missions/tier2-coding-bounds /missions/tier2-coding-bounds
COPY cloudflare/containers/verifier_server.py /opt/verifier_server.py

# Make /missions strictly read-only to the unprivileged `verifier` user.
RUN chmod -R a-w,a+rX /missions \
    && chmod a+rx /missions/tier1-metacomplexity-dag/verify /missions/tier1-crypto-algebra-dag/verify /missions/tier2-soundness-bound/verify /missions/tier2-coding-bounds/verify /opt/verifier_server.py \
    && useradd -m -u 10001 verifier \
    && mkdir -p /work \
    && chown verifier:verifier /work

USER verifier
WORKDIR /work
EXPOSE 8080
CMD ["python3", "/opt/verifier_server.py"]
