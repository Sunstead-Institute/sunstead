FROM --platform=linux/amd64 debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e

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

COPY missions/lnsym-aes-gcm-armv8 /missions/lnsym-aes-gcm-armv8
COPY missions/verifier-common/sunstead_sandbox.py missions/verifier-common/SunsteadCheck.lean missions/verifier-common/prebuild_snapshot.py /opt/sunstead/
COPY cloudflare/containers/verifier_server.py /opt/verifier_server.py

# Seeds, harness, native checker, prebuilt repo-snapshot `.olean` caches, and
# server are read-only. The server runs as root and drops to `sunstead-runner`
# for contributor compilation and `sunstead-checker` for kernel replay.
RUN SYSROOT="$(lean --print-prefix)" \
    && mkdir -p /tmp/scbuild \
    && lean -c /tmp/scbuild/SunsteadCheck.c /opt/sunstead/SunsteadCheck.lean \
    && leanc -O2 -o /opt/sunstead/sunstead-check /tmp/scbuild/SunsteadCheck.c \
       -lleanshared -Wl,-rpath,"${SYSROOT}/lib/lean" \
    && rm -rf /tmp/scbuild \
    && /opt/sunstead/sunstead-check selftest | grep -q '"selftest":"ok"' \
    && python3 /opt/sunstead/prebuild_snapshot.py /missions/* \
    && chmod -R a-w,a+rX /missions /opt/sunstead /opt/verifier_server.py \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10002 sunstead-runner \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10003 sunstead-checker \
    && mkdir -p /work && chmod 0755 /work

WORKDIR /work
EXPOSE 8080
CMD ["python3", "/opt/verifier_server.py"]
