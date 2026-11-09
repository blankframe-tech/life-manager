#!/usr/bin/env bash
# The only supported way to build the web app for hosting: scripts/build_web.sh
# Extra flags (e.g. --base-href /life-manager/) are passed to flutter build.
#
# pubspec bundles the whole assets/seed/ folder (the native seeder needs it),
# so a personal seed.json would be published in plaintext with the site.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -e assets/seed/seed.json ]; then
  echo "Refusing to build: assets/seed/seed.json exists and would be published" >&2
  echo "with the site. Move it out of assets/seed/ and run this again." >&2
  exit 1
fi

flutter build web --release --no-web-resources-cdn --csp --no-wasm-dry-run "$@"

if [ -e build/web/assets/assets/seed/seed.json ]; then
  echo "build/web contains seed.json; do not host this build." >&2
  exit 1
fi
echo "OK: build/web is ready to copy to an HTTPS host (see docs/WEB.md)."
