# Handoff — Life Manager (2026-08-09)

Branch `main`, clean, pushed. Cross-device sync is **live and verified** against a
real Supabase project. The app runs on the iOS simulator; neither physical phone
is installed yet.

## What it is

Offline-first Flutter app (iOS + Android) — Budget / Dealings / Tasks / Buy /
Dreams. Isar local DB is the source of truth; a background worker mirrors to
Supabase. Architecture and file map are in `README.md`.

## Environment — read this first

**Requires Flutter ≥ 3.44 (Dart ≥ 3.12.2).** `pubspec.yaml` sets
`sdk: ^3.12.2`; on Flutter 3.41 / Dart 3.11.5 `flutter pub get` fails outright
with a version-solve error. Verified working on Flutter 3.44.9 / Dart 3.12.x,
Xcode 26.6, Android SDK 37.

```bash
flutter pub get
dart run build_runner build     # generates lib/models/item.g.dart
```

`flutter analyze` clean; `flutter test` 9/9 pass (verified 2026-08-09).

## Sync: how to configure

Keys are compile-time `--dart-define` values read by
`lib/config/supabase_config.dart`. **This repo is public — never commit them.**
`.env` is git-ignored (`.gitignore:55`); keep it that way.

```bash
cp .env.example .env     # fill SUPABASE_URL + SUPABASE_ANON_KEY
./run.sh                 # sources .env, passes both as --dart-define
```

Bare `flutter run` does **not** read `.env` — it launches local-only. Extra args
pass through, so `./run.sh --release -d <device-id>` works.

`SupabaseConfig` accepts both modern `sb_publishable_…` keys and legacy `eyJ…`
anon JWTs; `main.dart:21-34` routes each to the right `Supabase.initialize`
parameter. With no keys the app is a fully working local-only tracker.

The schema in `supabase/schema.sql` has been applied to the live project: `items`
table, both indexes, the `supabase_realtime` publication, and the permissive RLS
policy. Ask the owner for the project URL and publishable key.

## Verified working (2026-08-09)

Tested end-to-end on the iOS simulator against the live project:

| Direction | How | Result |
|---|---|---|
| Local → cloud | app launch, seed push | 12 rows upserted |
| Cloud → local | REST `POST /items` | row appeared live in UI, totals recalculated |
| Delete | REST `PATCH is_deleted=true` | tombstone propagated, row hidden, totals reverted |

The app-bar cloud icon (`root_scaffold.dart:71` → `syncOnlineProvider`) turns
green when configured.

The live table currently holds **12 rows of fake example data** from
`assets/seed/seed.example.json`, not real user data. See "Seeding" below before
onboarding a real device.

## Fixed today — don't reintroduce these

1. **Invalid UUID namespace crashed every fresh launch** (`a6d01a4`).
   `seed_loader.dart` used `6f9619ff-8b86-d011-b42d-00c04fc964ff`, the MSDN
   sample GUID, whose version nibble is `d` (13) — not a valid RFC 4122 version.
   `uuid` 4.x validates before deriving a v5, so it threw `FormatException`.
   Because `seedIfNeeded` is awaited in `main.dart:41` *before* `runApp`, a fresh
   clone booted to a blank white screen. Now uses `Namespace.url.value`
   (`Uuid.NAMESPACE_URL` exists but is deprecated in uuid 4.x).

2. **Second device clobbered the first device's cloud data** (`7092fdc`).
   Seed uuids are deterministic v5 over `kind::title::index`, so a fresh install
   generates ids identical to an existing device's. Seeding ran before
   `SyncService` started, so phone 2's pristine rows carried a newer `updatedAt`,
   won last-write-wins on upsert, and realtime propagated the reset back to phone
   1. Now `seedIfNeeded` skips seeding when Supabase is configured unless the
   cloud table is empty; if the cloud is unreachable it seeds nothing and leaves
   the marker unwritten so the next launch retries.

3. **`run.sh` shipped without the exec bit** (`18b458d`) — documented `./run.sh`
   gave "permission denied".

## Gotchas

- **Hard deletes do not propagate.** `_applyRemote` (`sync_service.dart:85`)
  only upserts rows present in the stream payload; it never removes local rows
  absent from it. The app's own `delete()` sets `isDeleted = true`, which works.
  If you delete a row directly in the Supabase dashboard, clients keep it —
  `PATCH is_deleted=true` instead.
- **Seeding order decides canonical data.** The first device to launch against
  an empty cloud seeds it; every later device pulls instead. Bring up the device
  whose data you want to keep first.
- **`.seeded_v1` marker** in the app-support dir suppresses re-import forever.
  To re-seed you must delete the app from the device.
- **`_online` is latched at construction** (`sync_service.dart:22`) and there is
  no connectivity listener. If keys are present the engine considers itself
  online; failed pushes keep `isSynced = false` and retry on the next `save()`
  or Settings → "Sync now". A device that boots offline never re-arms until
  relaunch.
- **Conflict resolution is last-write-wins on `updatedAt`** with no merge. Two
  devices editing the same row concurrently: newest wall-clock write wins, the
  other edit is lost. Clock skew between devices therefore matters.
- **Android release signs with the debug keystore**
  (`android/app/build.gradle.kts:34`, TODO in place). Installs fine on your own
  phone; blocks Play Store.

## Open TODO

1. **Privacy hardening — do before real financial data.** `schema.sql:37` grants
   `anon` full read/write via `using (true)`. The publishable key is compiled
   into every APK/IPA and is extractable, so anyone with URL + key has full
   access to the budget and debt ledger. Fix is sketched at `schema.sql:47`: add
   Supabase Auth, a `user_id` column defaulting to `auth.uid()`, and an
   owner-only policy. Non-trivial — **the app has no login UI at all today**.
   Cheaper now than after rows exist on multiple devices.
2. **Install on physical devices.**
   - Android: `flutter build apk --release --dart-define=…`, then
     `~/Library/Android/sdk/platform-tools/adb install -r <apk>` (adb is not on
     PATH). Needs USB debugging + "install from unknown sources".
   - iOS: needs Developer Mode on the phone, a **cable** (wireless discovery
     fails with code -27), `cd ios && pod install`, and an Apple ID team under
     Runner → Signing & Capabilities. Free provisioning profiles expire after
     7 days.
3. **Replace the fake seed data** with real values in `assets/seed/seed.json`
   (git-ignored; `seed.example.json` shows the shape) — and truncate the live
   `items` table first, since the example rows are already canonical there.
4. Possible features: reorder, recurring items, budget carry-over.

## Decisions on record

- `isar_community` fork, not official `isar` — the official 3.1.0 generator
  ships a 2023-era analyzer that can't parse Dart 3.12 syntax. Drop-in same API.
- `path_provider_foundation` pinned to 2.3.2 in `dependency_overrides` — 2.5.0+
  pulls an Apple-only `objective_c` build hook that crashes when the Dart SDK
  path contains a space.
- One `items` table backs all five screens; each screen is a filtered Isar
  stream. Keeps local reads and sync trivial.
- Soft deletes (tombstones) so deletions propagate across devices.
