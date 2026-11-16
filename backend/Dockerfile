# The Ahead server as one small native binary.
#   docker build -f backend/Dockerfile -t ahead-server .     (from the repo root)
# The build context is the repo root, because server.dart imports
# ../lib/legal (privacy texts shared with the app). Only backend/ and
# lib/legal/ are copied; backend/Dockerfile.dockerignore keeps secrets out.
# Data (accounts, vault, waitlist, ...) lives in /app/.data: mount a volume there.
FROM dart:3.10 AS build
WORKDIR /src/backend
COPY backend/pubspec.yaml backend/pubspec.lock ./
RUN dart pub get
COPY backend/ ./
COPY lib/legal/ /src/lib/legal/
RUN dart compile exe server.dart -o /out/server

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home /app ahead
WORKDIR /app
COPY --from=build /out/server /app/server
RUN mkdir -p /app/.data /app/keys && chown -R ahead /app
USER ahead
ENV BIND=0.0.0.0 PORT=8090 TRUST_PROXY=1
EXPOSE 8090
CMD ["/app/server"]
