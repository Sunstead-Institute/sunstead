FROM debian:bookworm-slim

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

RUN useradd -m -u 10001 verifier && mkdir -p /work && chown verifier:verifier /work
USER verifier
WORKDIR /work
