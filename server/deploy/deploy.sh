#!/usr/bin/env sh
# Builds the Flutter web app, ships server/ to the Hetzner box and rebuilds
# the container there. Run from anywhere; needs the `hetzner` SSH alias.
#
#   sh server/deploy/deploy.sh            # full deploy
#   SKIP_WEB=1 sh server/deploy/deploy.sh # server-only change, reuse last web build
set -eu

cd "$(dirname "$0")/../.."

if [ -z "${SKIP_WEB:-}" ]; then
  echo "==> flutter build web --wasm"
  # Dart is compiled to WebAssembly with a dart2js fallback; flutter.js picks
  # at load time (Safari < 17 and browsers without WasmGC get main.dart.js).
  # The server deliberately sends no COOP/COEP headers: skwasm then runs
  # single-threaded instead of failing, and cross-origin Data Dragon icons
  # keep loading without CORP headers we don't control.
  flutter build web --release --wasm
fi
if [ ! -f build/web/index.html ]; then
  echo "build/web/index.html missing; run without SKIP_WEB" >&2
  exit 1
fi

echo "==> staging web build into server/web"
rm -rf server/web
cp -r build/web server/web

echo "==> uploading and building on the server"
tar -C server -czf - --exclude='*.db' --exclude='*.db-*' . |
  ssh hetzner 'set -e
    # Start from an empty tree: tar never deletes, so files removed here
    # would otherwise linger on the box and break the Go build.
    rm -rf /opt/undercover
    mkdir -p /opt/undercover
    tar -xzf - -C /opt/undercover
    cd /opt/undercover/deploy
    docker compose up -d --build --remove-orphans
    docker compose ps'

echo "==> done. Logs: ssh hetzner \"cd /opt/undercover/deploy && docker compose logs -f\""
