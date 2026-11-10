Frozen until the owner moves it to GTM: personal tool outside the November bet; only security fixes (LM-1 waits on the owner's go), LEARNINGS.md and a demo page. Call source: `~/Everything/dev/products/decision.md` (November bet, default A).

# AGENTS.md — Life Manager

Flutter app, iOS-first. Isar local DB, Riverpod. Data stays on the device;
Supabase sync exists but is off (`kCloudSyncEnabled` in `lib/app_modules.dart`).

- **Modules:** every feature is a `LifeModule` in `lib/modules/<name>/`, enabled
  and ordered in `lib/app_modules.dart`. Read [docs/MODULES.md](docs/MODULES.md)
  before adding, removing or reordering one.
- **Canvas** (branch `refresh`): the app can reshape itself from the user's
  own notes, chats and CSVs, offline. Code in `lib/canvas/`; read
  [docs/CANVAS.md](docs/CANVAS.md) before touching the shaper rules or the
  blueprint JSON. `test/canvas/` asserts on `lib/canvas/samples.dart`.
- **Theme:** colours come from `context.colors` / `ModuleAccent` in
  `lib/theme/app_theme.dart`. No raw hex in widgets. Keep text ≥ 4.5:1 (a test
  checks the tokens) and tap targets ≥ 44pt.
- **Storage:** read and write items through `LocalStore` (`storeProvider`),
  never Isar directly: the web build has no Isar. Web code lives in
  `lib/web/` and `lib/boot/boot_web.dart` and must never use browser storage
  (a test greps for it). See [docs/WEB.md](docs/WEB.md).
  Build a web copy for hosting only with `scripts/build_web.sh`.
- **Verify:** `scripts/check.sh` (identifier guard, pub get, codegen,
  analyze, test). Analyze must report 0 issues.
- **Public repo:** never commit `.env`, keys, `assets/seed/seed.json` or
  personal data (emails, the Supabase project ref; check.sh greps for them).
- More context: `README.md`, `HANDOFF.md`, `design_v2.md`.
