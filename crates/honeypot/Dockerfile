FROM rust:1.78-slim AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock* ./
COPY crates ./crates
RUN cargo build --release --bin lxon-honeypot

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates tini && rm -rf /var/lib/apt/lists/* && useradd -r -u 10001 -s /usr/sbin/nologin honeypot
COPY --from=builder /build/target/release/lxon-honeypot /usr/local/bin/lxon-honeypot
RUN mkdir -p /evidence && chown honeypot:honeypot /evidence
VOLUME ["/evidence"]
USER honeypot
EXPOSE 8081 8082 8083
ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/lxon-honeypot"]