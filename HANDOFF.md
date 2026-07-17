# HANDOFF — Life Manager

Everything you need to pick this up on a new machine. Written 2026-07-18.

## What it is
A fast, offline-first Flutter app (iOS-priority, Android too) — **Budget /
Dealings / Tasks / Buy / Dreams** — that syncs across devices. Local-first
(Isar) + Supabase realtime. See [`README.md`](README.md) for the full overview.

Repo: `https://github.com/blankframe-tech/life-manager` (branch `main`).

## Current status — ✅ working end to end
- Code complete; `flutter analyze` → **no issues**; **9/9 tests pass**.
- Supabase project **live and verified**: URL + publishable key valid, `items`
  table + indexes + realtime + access policy created, insert/read/delete proven
  through the REST API with the publishable key.
- **Your real data (71 rows) is already in Supabase** — 6 dealings, 13 budget,
  14 tasks, 36 buy, 2 dreams. It was uploaded with the *same* deterministic IDs
  the app generates, so it will never duplicate. A fresh clone that connects
  with the keys will pull all of it down.

## Resume on a new machine
1. `git clone https://github.com/blankframe-tech/life-manager && cd life-manager`
2. `flutter pub get`
3. `dart run build_runner build`   (generates `lib/models/item.g.dart`)
4. Recreate `.env` (it's git-ignored — see below), then:
   - `./run.ps1` (Windows) or `./run.sh` (macOS/Linux)
5. On first launch it pulls your 71 rows from Supabase. (It also seeds from a
   local `assets/seed/seed.json` if you restore that file — same IDs, so no
   duplicates either way.)

## Git-ignored files (NOT in the repo — recreate or restore)
| File | What it is | How to get it back |
|------|-----------|--------------------|
| `.env` | Supabase URL + publishable key | Recreate from `.env.example`; values below |
| `assets/seed/seed.json` | Your original list, verbatim | Optional now — the data is in Supabase. Keep a copy if you want the raw source text. |
| `NOTES.local.md` | The reordered plan + budget feedback | Optional — same content is in the app/Supabase. Keep a copy if you want the prose. |

### `.env` contents to recreate
```
SUPABASE_URL=https://utsbjdmhdfcdidlqurdl.supabase.co
SUPABASE_ANON_KEY=<publishable key>
```
- **Project ID:** `utsbjdmhdfcdidlqurdl`  (URL is `https://<id>.supabase.co`)
- **Publishable key:** Supabase Dashboard → Project Settings → **API Keys** →
  the `publishable` (a.k.a. anon/public) key. Safe to put in `.env`; never
  commit it, and never use the `secret` key in the app.

## Supabase
- Org `blankframe-tech`, project "blankframe-tech's life manager", region Seoul.
- Schema lives in [`supabase/schema.sql`](supabase/schema.sql) (already applied).
  Re-run it any time it's safe — it's idempotent (`create table if not exists`,
  `create index if not exists`).
- Realtime is enabled for `items`. If a second device doesn't update live,
  check Database → Replication.

## Key technical decisions (so you don't re-hit these)
- **Local DB is `isar_community`, not official `isar`.** Official `isar 3.1.0`
  ships a 2023-era analyzer that can't parse Dart 3.12 — its generator hard
  fails. The community fork is a drop-in (import `package:isar_community/isar.dart`).
- **`dependency_overrides: path_provider_foundation: 2.3.2`** in `pubspec.yaml`.
  Newer versions pull the Apple-only `objective_c` native-asset build hook,
  which crashes `flutter test`/`build` when the machine's SDK path contains a
  space (an upstream Dart bug). Pinning below that migration avoids it. Remove
  the override only on a machine whose path has no spaces if you want newer.
- **Supabase key handling:** `main.dart` sends `sb_…` keys via `publishableKey`
  and legacy `eyJ…` JWTs via `anonKey`.
- **One unified `Item` model** backs all five screens (`lib/models/item.dart`),
  and one Supabase `items` table. Each screen is a filtered stream over it.
  Deletes are soft (tombstones); conflicts resolve last-write-wins on
  `updated_at`.
- **No personal data in the repo.** Real names/amounts live only in the
  git-ignored `seed.json` + your Supabase DB. `seed.example.json` (fake) is
  committed so clones compile.

## Verification note
`flutter test` needs a Dart SDK install path with **no spaces**. On this machine
(`C:\Users\Abraar at Inovace\…`) the pure-logic tests pass; the full run works
because of the `path_provider_foundation` override above. On a normal path,
`flutter test` just works.

## Next steps / TODO
- **Ship to device:** iOS needs a Mac + Xcode (`cd ios && pod install`, then
  Xcode → Runner → Signing & Capabilities → auto-manage signing → your team;
  Podfile is already pinned to iOS 13). Android needs `flutter doctor
  --android-licenses` accepted once (minSdk is 33).
- **Privacy hardening (recommended — holds financial data):** the access policy
  is currently wide open (anyone with URL + publishable key can read/write). Add
  Supabase Auth (email magic-link) + a per-user `user_id` row policy — the exact
  SQL is commented at the bottom of `supabase/schema.sql`. This also means
  adding a login screen and stamping `user_id` on writes in `sync_service.dart`.
- **Rotate the `secret` key** if you ever shared it (Dashboard → API Keys). The
  app never uses it.
- **Possible features:** search/filter, reorder within a section (model already
  has `sortOrder`), recurring items, a monthly "carry-over" reset for budget.
