#!/usr/bin/env bash
# Launch the app with Supabase creds loaded from .env (see .env.example).
# Any extra args are passed through to `flutter run` (e.g. -d <device>).
set -euo pipefail
cd "$(dirname "$0")"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

exec flutter run \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
  "$@"
