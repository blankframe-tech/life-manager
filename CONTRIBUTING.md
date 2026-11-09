# Contributing to Life Manager

Thanks for helping. Active work happens on **`main`**, so base every branch and pull request on `main`.

## Setup

1. Install Flutter (stable) and clone the repo.
2. `flutter pub get`
3. `dart run build_runner build --delete-conflicting-outputs` (generates the Isar models)
4. `flutter run`. No keys are needed: cloud sync is off by default (`kCloudSyncEnabled` in `lib/app_modules.dart`).

## Checks

Run `scripts/check.sh` before you open a pull request. It fails if a personal email or a Supabase project URL is in the tree, then runs `flutter analyze` and `flutter test`; all must pass.

## Picking an issue

- Start with issues labelled `good first issue` or `help wanted`. Each has a difficulty label.
- Comment on the issue before you start, so two people don't do the same work.
- Read `AGENTS.md` and `docs/MODULES.md` for how the code is laid out: every feature is a module under `lib/modules/<name>/`.

## Pull requests

- One change per pull request, against `main`, with `Fixes #N` in the description.
- Add or update a test for the behaviour you change.
- Never commit real personal data, keys or a filled-in `.env`.
- Reviews are best effort.

By contributing you agree that your work is released under the repo's MIT license.
