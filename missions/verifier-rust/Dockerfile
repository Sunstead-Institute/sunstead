FROM rust:slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 10001 verifier && mkdir -p /work && chown verifier:verifier /work
USER verifier
ENV CARGO_TARGET_DIR=/tmp/cargo_target
WORKDIR /work
