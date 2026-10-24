# AGENTS.md — Life Manager

Flutter app, iOS-first. Isar local DB, Riverpod. Data stays on the device;
Supabase sync exists but is off (`kCloudSyncEnabled` in `lib/app_modules.dart`).

- **Modules:** every feature is a `LifeModule` in `lib/modules/<name>/`, enabled
  and ordered in `lib/app_modules.dart`. Read [docs/MODULES.md](docs/MODULES.md)
  before adding, removing or reordering one.
- **Theme:** colours come from `context.colors` / `ModuleAccent` in
  `lib/theme/app_theme.dart`. No raw hex in widgets. Keep text ≥ 4.5:1 (a test
  checks the tokens) and tap targets ≥ 44pt.
- **Storage:** read and write items through `LocalStore` (`storeProvider`),
  never Isar directly: the web build has no Isar. Web code lives in
  `lib/web/` and `lib/boot/boot_web.dart` and must never use browser storage
  (a test greps for it). See [docs/WEB.md](docs/WEB.md).
- **Verify:** `scripts/check.sh` (pub get, codegen, analyze, test). Analyze
  must report 0 issues.
- **Public repo:** never commit `.env`, keys, `assets/seed/seed.json` or
  personal data.
- More context: `README.md`, `HANDOFF.md`, `design_v2.md`.
