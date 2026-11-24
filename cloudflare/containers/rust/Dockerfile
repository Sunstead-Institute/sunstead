FROM --platform=linux/amd64 rust:slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends git python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY missions/tier3-mldsa-arith /missions/tier3-mldsa-arith
COPY missions/tier3-chacha-x509 /missions/tier3-chacha-x509
COPY cloudflare/containers/verifier_server.py /opt/verifier_server.py

# Make /missions strictly read-only to the unprivileged `verifier` user.
RUN chmod -R a-w,a+rX /missions \
    && chmod a+rx /missions/tier3-mldsa-arith/verify /missions/tier3-chacha-x509/verify /opt/verifier_server.py \
    && useradd -m -u 10001 verifier \
    && mkdir -p /work \
    && chown verifier:verifier /work

USER verifier
ENV CARGO_TARGET_DIR=/tmp/cargo_target
WORKDIR /work
EXPOSE 8080
CMD ["python3", "/opt/verifier_server.py"]
