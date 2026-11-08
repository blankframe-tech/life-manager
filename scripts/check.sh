#!/usr/bin/env bash
# Identifier guard + analyze + test. Run from anywhere: scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
# Public repo: no personal emails or Supabase project URLs (tracked or new files).
if git grep -n -I -i --untracked -E '@gmail\.com|[a-z]{20}\.supabase\.co' -- . ; then
  echo 'personal identifier committed' >&2
  exit 1
fi
flutter pub get >/dev/null
dart run build_runner build --delete-conflicting-outputs >/dev/null
flutter analyze
flutter test
