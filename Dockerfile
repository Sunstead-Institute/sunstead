# syntax=docker/dockerfile:1

FROM rust:slim-bookworm AS builder
WORKDIR /build

COPY Cargo.toml ./
COPY crates ./crates

RUN cargo test --workspace
RUN cargo build --release --bin sunstead-hub

FROM docker:27-cli AS dockercli

FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git curl sqlite3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=builder /build/target/release/sunstead-hub /usr/local/bin/sunstead-hub

WORKDIR /app
COPY missions /app/missions
COPY web /app/web

ENV PORT=8080 \
    SUNSTEAD_MISSIONS_DIR=/app/missions \
    SUNSTEAD_DATA_DIR=/app/data \
    SUNSTEAD_WEB_DIR=/app/web

EXPOSE 8080
CMD ["/usr/local/bin/sunstead-hub"]
