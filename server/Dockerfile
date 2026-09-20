# syntax=docker/dockerfile:1.7
# Build context is server/. deploy.sh copies the Flutter web build into
# server/web/ first, so the image serves both the WebSocket API and the site.

FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
# The cache mounts matter: modernc.org/sqlite takes minutes to compile on
# two vCPUs the first time and seconds afterwards.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go vet ./... && \
    CGO_ENABLED=0 go test ./... && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/undercover ./cmd/undercover
# A fresh named volume is seeded from the image's directory, and the
# nonroot user must be able to create the SQLite file in it.
RUN mkdir -p /out/data && chown 65532:65532 /out/data

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/undercover /undercover
COPY --from=build --chown=65532:65532 /out/data /data
COPY web/ /web/
ENV UNDERCOVER_ADDR=:8080 UNDERCOVER_DB=/data/undercover.db UNDERCOVER_WEB_DIR=/web
EXPOSE 8080
ENTRYPOINT ["/undercover"]
