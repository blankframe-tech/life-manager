#!/usr/bin/env bash
# Analyze + test. Run from anywhere: scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get >/dev/null
dart run build_runner build --delete-conflicting-outputs >/dev/null
flutter analyze
flutter test
