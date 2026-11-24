FROM --platform=linux/amd64 rust:slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends git python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY missions/tier3-mldsa-arith /missions/tier3-mldsa-arith
COPY missions/tier3-chacha-x509 /missions/tier3-chacha-x509
COPY missions/verifier-common/sunstead_sandbox.py /opt/sunstead/sunstead_sandbox.py
COPY cloudflare/containers/verifier_server.py /opt/verifier_server.py

# Seeds, harness and server are read-only. The server runs as root and never
# executes contributor code itself: `verify` drops to `sunstead-runner` for
# that, and the trusted checks run as `sunstead-checker`.
RUN chmod -R a-w,a+rX /missions /opt/sunstead /opt/verifier_server.py \
    && chmod -R a+rX /usr/local/cargo /usr/local/rustup \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10002 sunstead-runner \
    && useradd -M -d /nonexistent -s /usr/sbin/nologin -u 10003 sunstead-checker \
    && mkdir -p /work && chmod 0755 /work

WORKDIR /work
EXPOSE 8080
CMD ["python3", "/opt/verifier_server.py"]
