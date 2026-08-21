# Handoff — Life Manager (2026-08-11)

Branch `main`. Working tree has **uncommitted changes** implementing auth
hardening, a Buy→Dreams merge, an activity history log, and a
user-configurable budget split — see "What changed today" below before
committing/pushing. **Auth is now fully live**: Google Sign-In works
end-to-end, the RLS/history_events migration has been run against the real
Supabase project, and owner-only RLS is enforced. The app has been run on
both the iOS simulator and a physical iPhone
(`tech.blankframe.lifeManager`, free Apple ID provisioning).

## What it is

Offline-first Flutter app (iOS + Android) — Transactions / Budget / Dealings /
Tasks / Dreams (Dreams now also hosts the former Buy list as a "Shopping"
section).
Isar local DB is the source of truth; a background worker mirrors to
Supabase. Architecture and file map are in `README.md`.

## Environment — read this first

**Requires Flutter ≥ 3.44 (Dart ≥ 3.12.2).** `pubspec.yaml` sets
`sdk: ^3.12.2`; on Flutter 3.41 / Dart 3.11.5 `flutter pub get` fails outright
with a version-solve error. Verified working on Flutter 3.44.9 / Dart 3.12.x,
Xcode 26.6, Android SDK 37.

```bash
flutter pub get
dart run build_runner build     # generates lib/models/*.g.dart
```

`flutter analyze` clean; `flutter test` 10/10 pass (verified 2026-08-11).

## What changed today (2026-08-11) — not yet committed

1. **Fixed silent sync failures.** `SyncService.pushPending()` used to
   swallow every push error. It now tracks `lastError` (a `ValueNotifier`),
   and Settings' "Sync now" shows a SnackBar with a real pushed/failed count
   instead of doing nothing visible.
2. **Google Sign-In + owner-only RLS — done, verified end-to-end, migration
   run.** New `AuthGate`/`SignInScreen`/`AuthService`; `main.dart` now gates
   `RootScaffold` behind a signed-in session, but **only when Supabase is
   configured** — local-only installs are unaffected and never see a login
   screen. `SyncService` now considers itself "online" only when a real
   session exists (was: "keys existed at build time"), and retries pending
   pushes every 30s. See "Auth setup" below for exactly what was done and
   where it differed from the original plan. (Superseded 2026-08-17 — "online"
   has since been split into `enabled` + `reachable`; see "Offline tolerance".)
3. **Buy merged into Dreams.** The bottom nav is down to 4 tabs. The Dreams
   screen now renders a "Shopping" section (P0/Wishlist grouping, amounts,
   checkboxes — everything Buy had) above the Dreams card list; the FAB on
   that tab opens a 2-option sheet ("Add to shopping" / "Add a dream").
   `Item.kind` values (`buy`, `dream`) are unchanged — this was a screen
   composition change, not a data model change.
4. **New: Activity History.** Every create/edit/complete/delete now logs a
   `HistoryEvent` row (new Isar collection + Supabase table), surfaced at
   Settings → Activity History as a day-grouped log. Written from inside
   `SyncService.save()`/`delete()` so no screen had to change.
5. **New: configurable Needs/Wants/Savings split.** The Budget screen's
   65/15/20 target was a hardcoded constant; it's now a `BudgetSplit`
   (`lib/services/settings_service.dart`) persisted via `SharedPreferences`
   and editable in Settings → Budget (three "Needs/Wants/Savings %" fields,
   with a live "adds up to 100%" check). Defaults still to 65/15/20. The
   Budget screen's summary card also got a "Target split" label added above
   the per-category rows, to disambiguate them from the stacked bar above
   (which shows *actual spend share*, a different percentage — that's
   expected, not a bug, but the two were easy to confuse without a label).
6. **New: Needs items are checkable, and reset monthly.** Budget rows in the
   Needs category now have a checkbox (tick = paid), with a strikethrough
   and a "$x/$total paid" count in the section header. `lib/services/
   budget_reset_service.dart` un-ticks every Needs item on the first launch
   of a new calendar month (tracked via a `needs_reset_month` SharedPreferences
   marker, checked once at startup in `main.dart` before the widget tree
   builds). Wants/Savings rows are unchanged — no checkbox, not affected by
   the reset. The reset writes go straight to Isar (no `SyncService`
   instance exists yet at that point in startup) but still flag each item
   `isSynced = false` and log an `uncompleted` `HistoryEvent`, so the reset
   itself propagates to other devices and shows up in Activity History.
7. **Cleaned up stray local test data.** Four `HistoryEvent` rows left over
   from earlier manual QA (`itemUuid` values like `"qa-item-4"`, not real
   UUIDs) were blocking every sync push with
   `invalid input syntax for type uuid`. Removed via a temporary one-off
   cleanup in `main.dart` (run once, then reverted — not in the current
   diff). No real data was affected; verified `flutter analyze` clean and
   sync succeeding ("Already up to date") afterward.

## Transactions tab (2026-08-20)

New leftmost bottom-nav tab (`lib/screens/transactions_screen.dart`), which
pushed Budget one place right and made Transactions the tab the app opens on.
It's a plain log of money in and out — deliberately separate from Budget (a
*plan* for the month) and Dealings (who owes whom).

- **Data model: no migration.** Transactions are `Item` rows with
  `kind = 'txn'`, reusing columns that already exist: `direction` holds
  `spend`/`earn` (a new `TxnDirection`, alongside `DealDirection` — a row's
  `kind` decides which vocabulary applies), `category` holds the free-text
  category name, and **`due_date` holds the date the money moved**. That last
  one is the only non-obvious reuse, so it's read through
  `TxnFields.occurredAt` rather than directly. Adding an `occurred_at` column
  instead would have meant a hand-run Supabase migration, and until it was
  run every push would fail — i.e. it would break sync for *all* kinds, not
  just this one. Nothing in `supabase/` needs re-running for this feature.
- **Weekly rollup** lives in `lib/util/week.dart` as pure functions
  (`startOfWeek`, `rollupByWeek`, `weekLabel`) so it's testable without Isar —
  weeks run Monday→Sunday, newest first, and only weeks with entries appear.
  `test/txn_test.dart` covers it, plus the screen itself via an overridden
  `itemsProvider` stream (no Isar needed for a widget test).
- **Categories are per-device**, in SharedPreferences
  (`lib/services/txn_category_service.dart`), same as salary and the budget
  split — they do *not* sync. Because a transaction stores the category as
  text, a category deleted here (or created on another device) still displays
  and still counts in the rollup; `mergeUsedCategories` is what keeps such
  strays in the picker so editing an old row can't silently retag it. Manage
  them at Settings → Transactions → Categories.
- `Section` gained `singularLabel`, so the editor sheet says "New
  Transaction" rather than "New Transactions" (this also fixed the existing
  "New Tasks" / "New Dreams" wording).

## Auth setup — done (2026-08-11)

Google Sign-In is live and verified end-to-end on the iOS simulator
(`the.abraar.rar@gmail.com`), and the RLS/history_events migration has been
run against the real, live Supabase project. What actually happened,
including two things not covered by the original plan:

1. **Google OAuth client** — created in Google Cloud Console as originally
   planned (Web + iOS + Android client IDs, OAuth consent screen in Testing
   mode, no Firebase). Web client ID is `GOOGLE_SERVER_CLIENT_ID` in `.env`.
2. **`.env` pointed at the wrong Supabase project initially** — it had
   `SUPABASE_URL=https://snuyfoaigowarifbaqdk.supabase.co`, a project that
   doesn't exist in this account. Corrected to the real, live project
   (`utsbjdmhdfcdidlqurdl`) — check `.env` matches the project you see in
   the Supabase dashboard before assuming anything is misconfigured.
3. **iOS needed two fixes beyond the Web/iOS/Android client IDs above:**
   - `ios/Runner/Info.plist` needs `GIDClientID` (the iOS client ID) and a
     `CFBundleURLTypes` entry with the *reversed* iOS client ID as a URL
     scheme, or sign-in fails immediately with `PlatformException(No active
     configuration. Make sure GIDClientID is set in Info.plist...)`. Both
     are now in `Info.plist` — if you regenerate the iOS client ID, update
     both here.
   - Supabase Dashboard → Authentication → Providers → Google → **"Skip
     nonce checks"** was originally enabled here. Without it, sign-in failed
     with `AuthApiException: Passed nonce and nonce in id_token should either
     both exist or not.`, because the app passed no nonce while
     `google_sign_in` v7 on iOS put one in the ID token anyway.
     **Superseded — see "Nonce checks" below.** The app now supplies its own
     nonce, and the toggle was turned back **off** on 2026-08-11. Do not
     re-enable it.
4. **`supabase/migrate_auth_and_history.sql` was rewritten before running.**
   The original version assumed `items` only held fake seed data and
   `truncate`d it before adding `user_id`. By the time it actually ran, the
   table held 72 rows of real synced data, so it was rewritten to backfill
   `user_id` in place instead (safety-checked to abort unless exactly one
   row exists in `auth.users`, since this app is single-user by design — see
   "Decisions on record"). Verified zero data loss after running (72/72
   items retained, all with non-null `user_id`). The file in the repo now
   reflects the backfill version actually used, with a comment explaining
   why.
5. Rebuilt and reinstalled on the simulator; sign-in and sync both confirmed
   working, including a "Sync now" push that reports "Already up to date"
   with no error. From here on, `assets/seed/seed.json` only seeds the first
   device to sign in against an empty cloud — see `seed_loader.dart` /
   `AuthGate` for the timing fix that made this correct under owner-only RLS.

`supabase/schema.sql` describes the **end state** (owner-only RLS,
`history_events` table) for a brand-new project — it no longer matches what
was live on the existing project before the migration ran. Don't re-run
`schema.sql` against the existing project; the migration in
`migrate_auth_and_history.sql` is what actually ran, and both are
non-idempotent — don't run either one again against this project.

## Security hardening (2026-08-11, second pass)

A security review of the post-auth state turned up eight issues. All the
code-side fixes are in. Of the three items that needed a dashboard or a
credential, the two dashboard ones were done on 2026-08-11; only the release
keystore is outstanding.

**Fixed in code:**

| # | Issue | Fix |
|---|-------|-----|
| 1 | No nonce on the Google ID-token exchange (replay) | `AuthService` generates a 256-bit CSPRNG nonce, hands it to `GoogleSignIn.initialize` and the same value to `signInWithIdToken` |
| 2 | Refresh token in plaintext SharedPreferences | `SecureLocalStorage` / `SecureGotrueAsyncStorage` (`lib/services/secure_session_storage.dart`) move it to Keychain / Keystore, migrating any existing plaintext session on first launch |
| 3 | Release builds signed with the debug key | `android/app/build.gradle.kts` reads `android/key.properties`; falls back to the debug key with a loud warning |
| 4 | Backups could copy the DB and token off-device | `allowBackup="false"` + `res/xml/data_extraction_rules.xml` on Android; `excludeLocalDatabaseFromBackup()` in `AppDelegate.swift` for iCloud |
| 5 | No app lock over an unencrypted local DB | Optional biometric/passcode lock — Settings → Security. Isar 3 has no encryption support, so this is the available mitigation, not a substitute |
| 6 | Any Google account could sign up | `supabase/restrict_signups.sql` (allowlist + `auth.users` trigger) — **ran 2026-08-11**, plus "Allow new users to sign up" turned off in the dashboard |
| 7 | Raw exception strings shown in the UI | `describeSyncError` (`sync_service.dart`) and `AuthService.describeAuthError` return summaries; detail only in debug builds |
| 8 | Seed UUIDs collided across accounts | `SeedLoader` derives its v5 namespace from the owner's user id, keeping per-account determinism |

### Nonce checks

`google_sign_in` v7 takes the nonce on `initialize()` — which may only be
called once per process — **not** on `authenticate()`, so the nonce is
per-app-run rather than per-attempt. That's still enough to make an ID token
minted in another context useless against this project. Supabase compares the
`nonce` claim against the raw value first and a SHA-256 of it second, so
passing the same raw string to both sides is correct.

Passing a nonce is safe with the dashboard toggle in **either** state: while
"Skip nonce checks" is on, Supabase ignores the claim, so sign-in keeps working
exactly as before and only starts being *checked* once you turn it off. The
toggle is now **off** (verified off again after a page reload on 2026-08-11),
so the claim is being checked.

The existing signed-in session is not disturbed — `SecureLocalStorage.initialize`
moves it out of SharedPreferences into the Keychain on the next launch, so
there's no forced re-login.

**Done in the dashboard (2026-08-11):**

1. **"Skip nonce checks" turned off** — Authentication → Providers → Google.
   Confirmed still off after a full page reload. **Not yet verified with a
   live sign-in**, because that needs real Google credentials on a device. If
   sign-in regresses to `Passed nonce and nonce in id_token should either both
   exist or not.`, turn the toggle back on and re-check the plugin's nonce
   plumbing — that error means the app and Supabase disagree about the claim,
   not that the toggle is wrong.
2. **Signups restricted** — "Allow new users to sign up" turned off, and
   `supabase/restrict_signups.sql` run against the live project. The script is
   idempotent and safe to re-run.

   The allowlist holds **two** addresses. `restrict_signups.sql` only seeds
   `the.abraar.rar@gmail.com`; `abraar.ai.dev@gmail.com` was added by hand
   afterwards, because the script's own verification query flagged it as an
   existing account that was not on the list. That account owns no rows
   (0 items, 0 history events, one sign-in at creation) — the real data lives
   under `the.abraar.rar@gmail.com` (83 items, 9 history events). **If you
   ever re-run the script on a fresh project, it will not recreate the second
   entry.**

   The trigger was tested both ways inside a self-rolling-back `DO` block:
   a non-allowlisted address was rejected with `check_violation`, an
   allowlisted one was accepted. Nothing from the test was committed —
   re-verified afterwards that `allowed_emails` holds exactly the two real
   addresses and `auth.users` still holds exactly the two real accounts.

   Note the trigger fires on **INSERT only**. Existing accounts keep working
   even if removed from the allowlist; to actually revoke one, delete it from
   Authentication → Users.

**Still to do (needs you):**

1. **Create a release keystore** — this is the last outstanding item. Run this
   yourself so the password never passes through anyone else:

   ```
   keytool -genkey -v -keystore ~/life-manager-upload.jks \
     -keyalg RSA -keysize 4096 -validity 10000 -alias upload
   ```

   Then copy `android/key.properties.example` to `android/key.properties` and
   fill in `storePassword`, `keyPassword` (same value unless you chose
   otherwise), `keyAlias=upload`, and `storeFile` as an **absolute** path.
   Back up both the `.jks` and the password — losing either means you can
   never ship an update to the same Play listing.

   The Gradle wiring is already done and was proven end-to-end with a
   throwaway keystore: a release APK built and `apksigner` confirmed it was
   signed with that key rather than the debug key. Until `key.properties`
   exists, release APKs are debug-signed and must not be distributed.
   `key.properties`, `*.jks` and `*.keystore` are git-ignored.

`flutter_secure_storage` is pinned to `^10.3.1` on purpose: 11.0.0 requires
`compileSdk = 37`, which this project's AGP doesn't support. The Android
cipher defaults are the same either way. `local_auth` also forced
`MainActivity` to extend `FlutterFragmentActivity` — the biometric prompt is a
Fragment and throws `no_fragment_activity` under plain `FlutterActivity`.

## Offline tolerance (2026-08-17)

**Symptom:** the app demanded a fresh sign-in constantly, worst when offline.

**Cause:** `onAuthStateChange` carries two unrelated kinds of bad news, and the
app treated them as one. gotrue's `_doRefresh` emits an *event*
(`signedOut`) when the refresh token is genuinely rejected, but pushes a
*stream error* via `notifyException` for any **retryable** failure — i.e. every
token refresh that can't reach the server. It deliberately keeps
`_currentSession` intact when it does this, because nothing is wrong with the
session. `AuthGate` watched that stream through a `StreamProvider` whose
`error:` branch returned `SignInScreen`, so an offline refresh logged you out
of a perfectly valid session — and gotrue's 10s auto-refresh ticker
regenerated the error for as long as you stayed offline.

**Fix — separate "am I signed in" from "can I reach the server":**

- `lib/services/session_controller.dart` (new) is the only thing `AuthGate`
  reads. It seeds synchronously from `auth.currentSession` (already populated
  by then: `Supabase.initialize` awaits `SupabaseAuth.initialize`, which calls
  `setInitialSession` with the persisted session, expired or not), and it
  **ignores stream errors entirely**. The only route back to `SignInScreen` is
  an explicit `signedOut` event.
- `SyncService` splits the old `_online` into `enabled` (a session exists —
  pushes are worth attempting) and `reachable` (the last request got through);
  `online` is both. Offline it queues locally, probes every 30s and on app
  resume, and on the first success re-subscribes realtime — which re-emits a
  full snapshot, catching up on whatever changed while away.
- `_ensureFreshToken()` refreshes an expired access token before pushing, so a
  guaranteed 401 doesn't get reported as "Session expired — sign in again".
  gotrue de-duplicates concurrent refreshes of the same token, so racing its
  own ticker is safe.
- `isOfflineError` (`lib/util/net.dart`) is the shared test for "transport
  failure" vs "the server answered and said no". `AuthRetryableFetchException`
  **extends** `AuthException`, so it must be matched *before* it in
  `describeSyncError` / `describeAuthError` — otherwise offline renders as
  "sign in again", which is exactly the false alarm this all exists to kill.
- The cloud indicator now uses `ValueListenableBuilder` on
  `SyncService.isOnline`. The old `syncOnlineProvider` was a plain
  `Provider<bool>` that read `online` once and never rebuilt, so the icon was
  frozen at whatever it showed on launch.

Covered by `test/session_test.dart` (15 tests), including a burst of 50
consecutive refresh failures that must not sign the user out.

**Not changed, and deliberately:** a revoked or expired *refresh* token still
signs you out — that's the server's call, not a connectivity guess.

## Data export / import (2026-08-12)

Settings → **Data** has "Export data" and "Import data".
`lib/services/backup_service.dart` is the whole implementation; the UI is two
tiles plus a confirm dialog in `settings_screen.dart`.

**Format** — one JSON file. Both collections are serialized with the models'
existing `toMap()`, i.e. the same snake_case shape that goes to Supabase, and
read back with `fromMap()`. There is deliberately no second definition of
"an item outside Isar" to keep in step.

```json
{ "format": "life-manager-backup", "version": 1,
  "exportedAt": "...", "counts": {...},
  "items": [ /* items.toMap() */ ], "history": [ /* history.toMap() */ ] }
```

Deleted items (`is_deleted`) and the full history log are both included —
dropping tombstones would resurrect deleted items on the next import.

**Export** writes to the **temporary** directory, not Documents, then hands the
file to the share sheet (Save to Files / AirDrop / mail). That's on purpose:
the export is plaintext financial data, and Documents is precisely what the
backup-exclusion work above keeps out of iCloud and Android auto-backup. Temp
isn't backed up, and each export deletes the previous one so plaintext copies
don't pile up. **The file itself is unencrypted — where it lands is on you.**

**Import merges, never deletes.** Rules match `SyncService` exactly so a restore
behaves like receiving the rows from the cloud: items resolve last-write-wins on
`updated_at`, history is insert-if-absent (events are immutable). Everything
written is flagged `isSynced = false` and a push is kicked off immediately, so
an import propagates to the cloud and the other device.

`peek()` validates the file and reports its counts *before* the confirm dialog,
so choosing the wrong file fails up front rather than halfway through a write.
A single unparseable row is counted and skipped rather than aborting a large
restore, and the count is reported — the SnackBar distinguishes "nothing to
import, already up to date" from "imported 3, 1 unreadable".

To change the format incompatibly, bump `BackupService.formatVersion`; imports
accept that version and below, and refuse anything newer with a clear message.

### Delete all data (2026-08-12)

Settings → Data → **Delete all data**. `lib/services/reset_service.dart`, with
the confirmation in `lib/widgets/delete_everything_dialog.dart`.

Wipes items and history from the local DB **and the cloud**, clears every
preference (salary, split, theme, app lock), and signs out — back to the
sign-in screen as on a fresh install.

**⚠️ Requires `supabase/allow_history_delete.sql` to have been run.** That
script adds an owner-scoped DELETE policy to `history_events`, which until now
had none — the log was deliberately append-only at the database layer. Deleting
your own data was judged to matter more than tamper-evidence against yourself
in a single-user app, and the client could already delete every item. The
script documents the trade-off and how to revert. **Until it's run, the reset
refuses and deletes nothing**, with a message naming the script. It can't
silently half-work: if the cloud log survived, the next realtime subscribe
would re-download every history row and visibly undo the wipe.

Ordering exists to make partial failure impossible:

1. **cloud history first** — the only delete that can be *refused*, so it fails
   while everything is still intact
2. cloud items
3. local DB (`isar.clear()`)
4. `SeedLoader.markSeeded()` — without it the next launch sees an empty DB,
   calls it a first run, and re-imports `seed.json`, undoing the reset
5. `prefs.clear()`, then the caller invalidates the preference-backed providers
   so the UI drops to defaults rather than showing stale values
6. sign out last, since the cloud deletes need the session

Refused up front when Supabase is configured but there's no session: wiping
only the device would be actively misleading, because the next sync pulls it
all back. A local-only build (no keys) has no cloud and resets freely — the
dialog drops all mention of the cloud in that case.

The confirmation requires typing `DELETE` (case/space-insensitive — it guards
against accidents, not spelling). This is the one action in the app that
destroys another device's data, so a single mistaken tap must not be enough.

## Sync: how to configure

Keys are compile-time `--dart-define` values read by
`lib/config/supabase_config.dart`. **This repo is public — never commit them.**
`.env` is git-ignored (`.gitignore:55`); keep it that way.

```bash
cp .env.example .env     # fill SUPABASE_URL, SUPABASE_ANON_KEY, GOOGLE_SERVER_CLIENT_ID
./run.sh                 # sources .env, passes all three as --dart-define
```

Bare `flutter run` does **not** read `.env` — it launches local-only (no
login screen, no sync). Extra args pass through, so
`./run.sh --release -d <device-id>` works.

`SupabaseConfig` accepts both modern `sb_publishable_…` keys and legacy `eyJ…`
anon JWTs; `main.dart` routes each to the right `Supabase.initialize`
parameter. `GoogleAuthConfig.isConfigured` is independent of
`SupabaseConfig.isConfigured` — if you set Supabase keys but skip the Google
client ID, the app will show a sign-in screen whose button doesn't work, so
set both together (see "Auth setup" above).

## Verified working

**2026-08-12, physical iPhone (current state).** Built and launched on
`Abraar's iPhone` (iOS 27.0) via `./run.sh -d <id>`, debug build, free Apple ID
provisioning. Clean launch, zero unhandled exceptions.

- **Session migrated to the Keychain with no re-login.** The first device run
  logged `Supabase init completed` followed by `Refresh session` and carried
  straight on into the app — i.e. `SecureLocalStorage.initialize` found the old
  plaintext session in SharedPreferences, moved it into the Keychain, and the
  refresh succeeded. This is the migration path in fix #2, confirmed on real
  hardware rather than reasoned about.
- **Found and fixed a realtime bug** — see below. Present before the security
  pass; it only became visible by running on the device.
- `flutter analyze` clean, `flutter test` 28/28, iOS simulator + Android
  debug/release all build.

**Not verified — needs a manual tap, so it's on you:**

1. **Sign-out → sign-in**, which is the only thing that exercises the nonce
   (fix #1). The device is signed in from a persisted session, so the Google
   flow never ran. If sign-in fails with `Passed nonce and nonce in id_token
   should either both exist or not.`, the nonce plumbing regressed.
2. **Settings → Data → Export**, then Import the same file back. A re-import of
   an unchanged export should report *"Nothing to import — everything was
   already up to date"*, which also proves the merge is idempotent.
3. **Settings → Security → Require unlock** — the biometric prompt itself can't
   be driven from a test harness. Gate logic has unit coverage
   (`test/app_lock_test.dart`), the Face ID prompt does not.

### Realtime subscribed with an expired JWT (fixed 2026-08-12)

On the first device run, both realtime channels died at startup:

```
RealtimeSubscribeException(status: channelError,
  details: Exception: "InvalidJWTToken: Token has expired 7685 seconds ago")
RealtimeSubscribeException(status: timedOut, details: null)
```

Cause: `SyncService`'s constructor started realtime whenever a session merely
*existed*, and at cold start the persisted access token is routinely expired
(the refresh lands a moment later). Worse, the auth listener only restarted
realtime on the offline→online transition, so `tokenRefreshed` never re-armed
it — the channels stayed dead until the next app launch, silently. Local writes
still pushed; **inbound** changes from the other device simply never arrived.

Fix: don't subscribe on an expired token, and re-subscribe on
`AuthChangeEvent.tokenRefreshed` as well as on the offline→online transition,
because a channel binds its JWT at subscribe time. Verified on device: a
subsequent launch with a valid token subscribed cleanly, zero exceptions.

Not fully exercised: the *expired-token-at-startup* branch needs a token older
than an hour to reproduce, so it's compiled and reasoned but not re-observed
failing-then-recovering on device. Watch for `InvalidJWTToken` after leaving
the app closed overnight.

**2026-08-11, post-auth-hardening (superseded by the above):** Google Sign-In on iOS
simulator, session persists across app restarts, `SyncService` reports
"Online" with a real session, "Sync now" pushes cleanly with no errors
(72 real items retained through the RLS migration, 0 with a null
`user_id`), and the Settings budget-split fields persist correctly across
restart.

**2026-08-09, pre-auth-hardening state (superseded):** Tested end-to-end on
the iOS simulator against the live project, back when RLS was still
permissive:

| Direction | How | Result |
|---|---|---|
| Local → cloud | app launch, seed push | 12 rows upserted |
| Cloud → local | REST `POST /items` | row appeared live in UI, totals recalculated |
| Delete | REST `PATCH is_deleted=true` | tombstone propagated, row hidden, totals reverted |

## Fixed previously — don't reintroduce these

1. **Invalid UUID namespace crashed every fresh launch** (`a6d01a4`).
   `seed_loader.dart` used `6f9619ff-8b86-d011-b42d-00c04fc964ff`, the MSDN
   sample GUID, whose version nibble is `d` (13) — not a valid RFC 4122 version.
   `uuid` 4.x validates before deriving a v5, so it threw `FormatException`.
   Now uses `Namespace.url.value`.
2. **Second device clobbered the first device's cloud data** (`7092fdc`).
   Seed uuids are deterministic v5 over `kind::title::index`, so a fresh
   install without this fix would generate ids identical to an existing
   device's and win last-write-wins with a newer `updatedAt`. Now
   `seedIfNeeded` skips seeding when Supabase is configured unless the cloud
   table is empty.
3. **`run.sh` shipped without the exec bit** (`18b458d`).
4. **iOS release build silently landed in the wrong directory**
   (`build/ios/Release-iphoneos/Runner.app` instead of the
   `build/ios/iphoneos/Runner.app` Flutter's tooling expects), making
   `flutter run --release -d <device>` fail with "Could not find the built
   application bundle" — a stale Xcode build-system cache issue. Fixed by
   `flutter clean && flutter pub get` before the release build.
5. **Free Apple ID provisioning caps installed apps at 3.** `devicectl`
   install failed with `ApplicationVerificationFailed` until an old app was
   deleted from the phone to free a slot — not a code bug, just a quota to
   remember when reinstalling.

## Gotchas

- **Hard deletes do not propagate.** `_applyRemote` only upserts rows
  present in the stream payload; it never removes local rows absent from
  it. The app's own `delete()` sets `isDeleted = true`, which works. If you
  delete a row directly in the Supabase dashboard, clients keep it —
  `PATCH is_deleted=true` instead.
- **Seeding order decides canonical data.** The first device to sign in
  against an empty (post-migration) cloud seeds it; every later device
  pulls instead.
- **`.seeded_v1` marker** in the app-support dir suppresses re-import
  forever. To re-seed you must delete the app from the device.
- **Conflict resolution is last-write-wins on `updatedAt`** with no merge.
  Two devices editing the same row concurrently: newest wall-clock write
  wins, the other edit is lost. Clock skew between devices therefore
  matters. `HistoryEvent` rows are append-only/immutable, so this doesn't
  apply to the activity log itself.
- **Data is siloed per Google account.** RLS is `user_id = auth.uid()` —
  signing into a different Google account on a different device sees an
  empty dataset, not shared data. This app assumes one person, one account,
  across all their devices.
- **`google_sign_in` is on the v7 API** (event-stream / `GoogleSignIn.instance`,
  not the old v6 singleton `signIn()` call) — if you ever look up
  `google_sign_in` examples online, make sure they're for v7+, the shape is
  materially different.
- **Android release still signs with the debug keystore** until you create
  `android/key.properties` (see "Still to do" above). The Gradle wiring reads
  that file and falls back to the debug key with a loud warning, so this is a
  missing credential, not missing code. Installs fine on your own phone;
  blocks Play Store. Also means the Android Google OAuth client's SHA-1
  fingerprint only needs the debug keystore's for now — when you generate the
  upload key, add its SHA-1 to the OAuth client too, or Google sign-in will
  fail in release builds.

## Open TODO

1. ✅ ~~Run the Google OAuth + RLS migration~~ — done, see "Auth setup" above.
2. **Install on physical devices.**
   - ✅ iOS: done, `tech.blankframe.lifeManager` on a personal iPhone via
     free Apple ID provisioning (`flutter run --release -d <device-id>`,
     after the `flutter clean` fix above). Note: free provisioning profiles
     expire after 7 days, and free accounts cap at 3 installed apps at once.
     Not yet reinstalled since the auth changes landed — do that next, using
     `./run.sh --release -d <device-id>` so the `.env` values get passed.
   - ⬜ Android: `flutter build apk --release --dart-define=…`, then
     `~/Library/Android/sdk/platform-tools/adb install -r <apk>` (adb is not
     on PATH). Needs USB debugging + "install from unknown sources".
3. **Replace the fake seed data** with real values in `assets/seed/seed.json`
   (git-ignored; `seed.example.json` shows the shape). The 72 real items
   already synced during testing were kept (backfilled, not truncated — see
   "Auth setup"), so this is now about the seed file used for *future* fresh
   installs, not a live-data concern.
4. Possible features: reorder, recurring items, budget carry-over, and for
   Transactions: a monthly rollup alongside the weekly one, and syncing the
   category list (today it's per-device, by design — see "Transactions tab").

## Decisions on record

- `isar_community` fork, not official `isar` — the official 3.1.0 generator
  ships a 2023-era analyzer that can't parse Dart 3.12 syntax. Drop-in same API.
- `path_provider_foundation` pinned to 2.3.2 in `dependency_overrides` — 2.5.0+
  pulls an Apple-only `objective_c` build hook that crashes when the Dart SDK
  path contains a space.
- One `items` table backs Transactions/Budget/Dealings/Tasks/Buy/Dreams; each
  screen is a filtered Isar stream. New kinds reuse the existing generic
  columns (`direction`/`category`/`due_date`) rather than adding columns, so
  a feature never ships blocked on a hand-run Supabase migration. A second table, `history_events`, is a separate
  append-only log — deliberately not folded into `items`, since it has no
  soft-delete/update semantics and different RLS (insert+select only).
- Soft deletes (tombstones) so deletions propagate across devices.
- Auth is Google-only, no email/password — matches "one person, their own
  Google account" as the actual usage model; adding a second provider or
  multi-user sharing is out of scope unless that changes.
- History logging lives in `SyncService`, not in the screens — every
  mutation already funnels through `save()`/`delete()`, so this was the one
  place that guarantees no action is missed regardless of which screen
  triggered it.
