# Contributing to Life Manager

Thanks for helping. Active work happens on the **`V2`** branch. `main` is the old V1, so base every branch and pull request on `V2`.

## Setup

1. Install Flutter (stable) and clone the repo.
2. `git checkout V2`
3. `flutter pub get`
4. `dart run build_runner build --delete-conflicting-outputs` (generates the Isar models)
5. `flutter run`. No keys are needed: cloud sync is off by default (`kCloudSyncEnabled` in `lib/app_modules.dart`).

## Checks

Run `scripts/check.sh` before you open a pull request. It runs `flutter analyze` and `flutter test`, and both must pass.

## Picking an issue

- Start with issues labelled `good first issue` or `help wanted`. Each has a difficulty label.
- Comment on the issue before you start, so two people don't do the same work.
- Read `AGENTS.md` and `docs/MODULES.md` for how the code is laid out: every feature is a module under `lib/modules/<name>/`.

## Pull requests

- One change per pull request, against `V2`, with `Fixes #N` in the description.
- Add or update a test for the behaviour you change.
- Never commit real personal data, keys or a filled-in `.env`.
- Reviews are best effort.

By contributing you agree that your work is released under the repo's MIT license.
