# Life Manager in the browser

The web build opens the same encrypted vault the iPhone app keeps
(`LifeManager.lmvault`, format in [VAULT_FORMAT.md](VAULT_FORMAT.md)) in
Safari, Firefox or Chrome, with the same V2 screens and modules. It is static
files only. There is no backend, and no data is ever stored on a web server
or in the browser.

## How it works

1. You open the site. It is a static Flutter web build: HTML, JS, WebAssembly
   (CanvasKit) and fonts, all served from the same origin.
2. "Log in" = pick your `.lmvault` file (from iCloud Drive or a download) and
   type its passphrase. The browser derives the key (PBKDF2-SHA256, 600,000
   rounds) and decrypts (AES-256-GCM) with WebCrypto, through the
   `cryptography` package. The rows go into an in-memory store.
3. You use the normal app. Edits change only that in-memory copy, and a
   red **Unsynced changes** badge appears in the top bar.
4. **Sync** re-encrypts everything with a fresh random nonce and writes it:
   - **Chrome / Edge** (File System Access API): back to the same file,
     after the browser asks once for permission. If the file changed since
     you opened it (for example, the iPhone saved it), it is decrypted and
     merged first, newer edit wins, exactly like `VaultService` on the
     phone. If it can't be decrypted, nothing is written.
   - **Safari / Firefox**: the browser downloads `LifeManager.lmvault`. Save
     it over the old file in iCloud Drive › Life Manager, or AirDrop it to
     the iPhone. The app merges it when you open it (last-write-wins). If the
     browser renamed it ("LifeManager (1).lmvault"), rename it back.
     The download path can't see the original file, so it can't merge
     changes the iPhone made in the meantime. The iPhone merges when it opens
     the file, so nothing is lost; the newer edit of each item wins.

A new vault ("Create a new vault", passphrase at least 10 characters,
entered twice) lives in memory until the first Sync, which asks where to
save it (Chrome) or downloads it (Safari / Firefox).

Code: `lib/boot/boot_web.dart` (startup), `lib/web/` (login, vault session,
browser glue, guardrails), `lib/store/memory_store.dart` (the store).

## Build

```bash
flutter pub get
flutter build web --release --no-web-resources-cdn --csp --no-wasm-dry-run
```

- `--no-web-resources-cdn` serves CanvasKit from `build/web/canvaskit/`
  instead of `gstatic.com`. Without it the CSP blocks the renderer.
- `--csp` keeps dart2js output free of `eval`.
- Output: `build/web/`. Try it locally with
  `cd build/web && python3 -m http.server 8000`, then open
  `http://localhost:8000` (WebCrypto needs `localhost` or HTTPS).

Tests:

```bash
scripts/check.sh                                   # VM: analyze + all tests
flutter test --platform chrome test/web/vault_codec_browser_test.dart \
  test/web/guards_test.dart test/store             # WebCrypto, web models
```

## Host it

Copy `build/web/` to any static host: GitHub Pages, Netlify, S3, a USB
stick with a local server. Since the server only hands out the app's code,
any static host works. Use HTTPS (WebCrypto and the File System Access API
need a secure context). For a sub-path such as GitHub Pages project sites,
build with `--base-href /life-manager/`.

Nothing is deployed from this repo.

## Threat model

What it protects:

- **The server and its operator** never see your data. They serve code; the
  vault never goes up, and the app makes no requests at all except for its
  own files.
- **Someone at the computer after you leave.** The session locks (key and
  every decrypted row dropped, back to the login screen) after 10 minutes
  without input, after 5 minutes with the tab hidden, or with the Lock
  button. Nothing survives a reload or closing the tab.
- **Someone who gets a copy of the file.** They need the passphrase. Each
  guess costs 600,000 PBKDF2 rounds. A wrong passphrase and a tampered file
  both fail AES-GCM authentication.

What it does not protect against:

- **A modified copy of the app.** Whoever controls the host (or a CDN in
  front of it) could serve code that steals the passphrase. Host it
  yourself, or on a host you trust, over HTTPS. The repo is public, so the
  build can be reproduced and compared.
- **A compromised browser or computer** (malware, a malicious extension,
  a keylogger). Use a browser profile without extensions you don't trust.
- **Offline guessing of a weak passphrase.** The login backoff only slows
  guesses typed into this tab. Anyone with the file can guess offline as
  fast as their hardware allows. The KDF cost and a long passphrase are the
  real defence.
- **Memory inspection while unlocked.** The passphrase stays in memory for
  the session (needed to merge a file the iPhone re-saved with a new salt).
  On lock the key bytes are zeroed and everything is released to the
  garbage collector; JavaScript can't wipe strings on demand.
- **Downloads.** Safari / Firefox Sync puts the encrypted file in your
  Downloads folder. It is ciphertext, but delete old copies you don't need.

## Guardrails

| Guardrail | Where |
|---|---|
| Login screen: logo, "Open your vault", file picker, passphrase, "Create a new vault" with confirm and a 10-character minimum | `lib/web/login_screen.dart` |
| Privacy note: "Your data never leaves this browser except as the encrypted file you save." | login screen, Settings → Storage |
| Wrong passphrase: exponential backoff, 1 s doubling to 5 min, field cleared. The comment says honestly that the KDF is the real defence | `PassphraseThrottle`, `lib/web/guards.dart` |
| Auto-lock: 10 min idle, 5 min hidden. Lock drops the key, the passphrase and the in-memory store, disposes every provider (a new `ProviderScope` per session) and returns to login. An auto-lock with unsynced changes saves first (in place if the browser already allows it, else an encrypted download) | `AutoLockPolicy`, `lib/web/web_app.dart` |
| Lock button in the top bar. With unsynced changes it asks: Sync and lock / Lock without syncing / Cancel | `lib/web/web_app.dart` |
| Unsynced changes: red badge and a Sync button in the top bar; `beforeunload` warns before closing or reloading | `lib/web/web_app.dart`, `guardUnload` in `lib/web/browser.dart` |
| Nothing in localStorage, sessionStorage, IndexedDB, cookies or the URL. Preferences use an in-memory store (`InMemorySharedPreferencesStore`), so the shared_preferences web plugin never writes localStorage | `lib/boot/boot_web.dart`; checked by `test/web/no_browser_storage_test.dart` (greps the web sources) and by the e2e run (checks the live page) |
| Strict CSP meta (`default-src 'self'`, `script-src 'self' 'wasm-unsafe-eval'`, `connect-src 'self' blob:`, `object-src 'none'`, `form-action 'none'`, `base-uri 'self'`) and `referrer: no-referrer` | `web/index.html` |
| No third-party requests: CanvasKit local, app fonts bundled, the fallback font subsets the UI needs (taka sign, symbols, emoji) self-hosted in `web/fonts/fallback/` (OFL, see `LICENSES.txt`), no service worker, no analytics | `web/flutter_bootstrap.js`, `web/fonts/` |
| Remote `<script>` injection dropped: google_sign_in's web part (needed on iOS) injects Google's GIS script at startup; `web/no_remote_scripts.js` drops any cross-origin script before the browser fetches it (the CSP would block it anyway) | `web/no_remote_scripts.js` |
| Native-only features are absent on the web: Keychain, app lock (Face ID), Supabase sign-in and sync, open-in from Files, Export/Import JSON (plaintext), Delete all data, the month-start Needs reset (the phone does it) | `lib/boot/boot_web.dart`, `kIsWeb` in `settings_screen.dart` |

Known limits:

- Text in a script none of the bundled or self-hosted fonts cover (for
  example Arabic or Thai) shows as boxes rather than fetching a font from
  Google. To support one, copy the file the engine asks for (a 404 under
  `fonts/fallback/`) from `https://fonts.gstatic.com/s/<same path>` into
  `web/fonts/fallback/`.
- Per-device settings (salary, budget split, transaction categories, theme,
  name) are not in the vault, so the web starts with defaults each session.
- Haptics are a no-op in the browser.

## Storage seam

Items and history go through `LocalStore` (`lib/store/local_store.dart`):
`IsarStore` on iOS / Android, `MemoryStore` on the web. `Item` and
`HistoryEvent` have a web twin without Isar (`*_web.dart`), selected by a
conditional import in `item.dart` / `history_event.dart`, because Isar's
generated 64-bit schema ids don't compile to JavaScript. Field mapping
(`itemToMap` / `itemFromMap`) is shared, so a field missing from either twin
fails the build on that platform. The analyzer resolves conditional imports
for the VM only, so `analysis_options.yaml` excludes the two twins; the
Chrome tests and `flutter build web` type-check them.
