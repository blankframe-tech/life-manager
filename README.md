# Life Manager

A fast, **offline-first** personal life manager for iOS and Android, built with
Flutter. It organizes five things and **syncs them across your devices**:

| Tab | What it holds |
|-----|---------------|
| **Budget**   | A 65 / 20 / 15 monthly plan (Needs / Savings / Wants) with live ideal-vs-actual bars |
| **Dealings** | A *Dena Paona* ledger — who you owe, who owes you, and your net position |
| **Tasks**    | To-dos grouped into Time-sensitive · Admin & tech · Declutter/repairs, with due dates |
| **Buy**      | Shopping split into Priority-0 (must-asap) and a Wishlist, with checkoff |
| **Dreams**   | Big long-term wishes |

Everything reads and writes to an on-device database **instantly** (0 ms — the
UI never waits on the network); a background worker syncs to the cloud when
online. Open the app on a second device signed into the same backend and edits
appear live.

## Architecture

```
        Flutter UI  (Riverpod — reactive, iOS-first Cupertino styling)
               │  watches Isar streams (instant)
               ▼
        Isar (isar_community)  ──►  SyncService  ──►  Supabase (Postgres + Realtime)
        on-device, source of truth   push pending      cloud mirror, one `items` table
                                      pull realtime      last-write-wins on updated_at
```

- **Local DB:** `isar_community` (maintained fork of Isar — the official
  `isar` 3.1.0 ships a 2023-era analyzer that can't parse Dart 3.12; the fork is
  a drop-in with the same API).
- **Cloud:** Supabase — a single `items` table backs all five screens. Deletes
  are soft (tombstones) so they propagate. Conflicts resolve last-write-wins on
  `updated_at`.
- **State:** Riverpod. Each screen is a filtered stream over the one collection.
- **Offline:** with no Supabase keys the app is a fully working local tracker;
  add keys later and it starts syncing.

Key files: `lib/models/item.dart` (unified record + JSON mapping),
`lib/services/sync_service.dart` (the sync engine), `lib/providers/providers.dart`,
`lib/data/seed_loader.dart` (one-time first-launch import), `lib/screens/*`.

## Run it

```bash
flutter pub get
dart run build_runner build            # generates lib/models/item.g.dart
flutter run                            # local-only (no cloud) — works out of the box
```

To enable cloud sync, put your keys in a `.env` file (kept out of source) and
use the launch script, which reads `.env` and passes the keys to Flutter:

```bash
cp .env.example .env      # then fill in SUPABASE_URL and SUPABASE_ANON_KEY
./run.ps1                 # Windows
./run.sh                  # macOS / Linux   (pass -d <device> to target one)
```

Get the two values from the Supabase dashboard → **Project Settings → API**:
`SUPABASE_URL` = the *Project URL*, `SUPABASE_ANON_KEY` = the *anon public* key.
(The database password is **not** used by the client app.) You can also skip
`.env` and pass `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
directly. With no keys, the app runs fully offline (local-only).

### Supabase setup (once)

1. Create a project at supabase.com.
2. **SQL Editor → New query →** paste [`supabase/schema.sql`](supabase/schema.sql) → **Run.**
   This creates the `items` table, indexes, realtime, and a policy.
3. Realtime is enabled by the schema (`alter publication ... add table items`).
   If a second device doesn't update live, check **Database → Replication** and
   confirm `items` is in the `supabase_realtime` publication.

### Seeding your own data (optional)

On first launch the app imports `assets/seed/seed.json` if present. That file is
**git-ignored** (it holds personal data). A fake [`seed.example.json`](assets/seed/seed.example.json)
is committed to show the shape — copy it to `seed.json` and edit. The seed runs
once (guarded by a marker) and uses deterministic IDs, so it never duplicates.

## Shipping to real devices

- **iOS (needs a Mac + Xcode):** `cd ios && pod install`. The [`Podfile`](ios/Podfile)
  already pins `platform :ios, '13.0'` (Isar needs iOS 13+). Open
  `ios/Runner.xcworkspace`, select **Runner → Signing & Capabilities**, tick
  **Automatically manage signing**, and pick your Apple ID team. Then run.
- **Android:** `minSdk` is set to **33 (Android 13)** in
  `android/app/build.gradle.kts`.

## Making it private (recommended)

The MVP schema uses a permissive policy so sync works with just the anon key and
no login. Because this app holds financial data, adding **Supabase Auth** (email
magic-link) plus a per-user `user_id` row policy is the recommended next step —
see the commented block at the bottom of `supabase/schema.sql`.

## Tests

```bash
flutter test          # requires a Dart SDK whose install path has no spaces
```

> Note: on Windows, if your user profile path contains a space (e.g.
> `C:\Users\First Last\`), `flutter test` currently fails while building the
> Apple-only `objective_c` native-asset hook (an upstream Dart bug — the SDK
> path is passed to the shell unquoted). The pure-logic tests
> (`test/format_test.dart`, `test/model_test.dart`) still pass on any machine or
> CI without a space in the path.
