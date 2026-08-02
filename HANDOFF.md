# Handoff — Life Manager status (2026-08-02)

Repo clean, branch `main` up to date with origin. Last commit `fb6793a`
(added HANDOFF.md). No changes since.

## What it is
Offline-first Flutter app (iOS + Android) — Budget / Dealings / Tasks / Buy /
Dreams — Isar local DB, Supabase realtime sync. Full details in
`README.md`.

## Status
- Code complete. `flutter analyze` clean, 9/9 tests pass (last verified 2026-07-18).
- Supabase live and verified: `items` table, indexes, realtime, policy all
  applied. 71 real rows already synced (6 dealings, 13 budget, 14 tasks, 36
  buy, 2 dreams), deterministic IDs so no dup risk.
- Source files: `lib/models/item.dart` (unified model), `lib/services/sync_service.dart`
  (sync engine), `lib/screens/*` (5 screens), `lib/data/seed_loader.dart`
  (first-launch import).

## Key decisions on record
- `isar_community` fork used, not official `isar` (analyzer can't parse Dart 3.12).
- `path_provider_foundation` pinned to 2.3.2 (Windows space-in-path bug workaround).
- Supabase key handling supports both new `sb_…` publishable keys and legacy `eyJ…` JWT.

## Open TODO
- Ship to device: iOS needs Mac/Xcode + pod install + signing; Android needs
  `flutter doctor --android-licenses`.
- Privacy hardening: access policy currently open (URL + key = full access).
  Add Supabase Auth + per-user row policy — SQL commented in `supabase/schema.sql`.
- Rotate Supabase `secret` key if ever shared.
- Possible features: search/filter, reorder, recurring items, budget carry-over.
