# Life Manager vault format (`.lmvault`, version 1)

One file holds all app data, encrypted with a passphrase. It is designed so a
browser can read and write it with **WebCrypto alone** (no libraries).

Reference implementation: `lib/vault/vault_codec.dart`.
Test vectors: `test/vault/vectors/*.json`, plus `test/vault/vectors/sample.lmvault`
(passphrase `correct horse battery staple`, 600,000 iterations).

## Byte layout

| Offset | Length | Content |
|---|---|---|
| 0 | 4 | Magic: ASCII `LMV1` (`4C 4D 56 31`) |
| 4 | 4 | `H`: header length in bytes, unsigned 32-bit **big-endian** |
| 8 | `H` | Header: UTF-8 JSON object (below) |
| 8 + `H` | rest | AES-GCM output: ciphertext followed by the 16-byte tag |

- **Associated data (AAD)** = bytes `0 .. 8 + H` (magic, length and header
  JSON exactly as stored). Any change to the header fails decryption.
- The ciphertext is as long as the plaintext. The last 16 bytes of the file are
  the GCM tag. WebCrypto's `encrypt` already returns `ciphertext || tag`, and
  `decrypt` expects the same, so the tail can be passed through unchanged.
- Readers must reject: a wrong magic, `H > 65536`, a file shorter than
  `8 + H + 16`, header JSON that doesn't parse.

## Header JSON

```json
{
  "version": 1,
  "kdf": "PBKDF2-HMAC-SHA256",
  "iterations": 600000,
  "salt": "<base64, 16 bytes>",
  "cipher": "AES-256-GCM",
  "nonce": "<base64, 12 bytes>",
  "createdAt": "2026-10-24T00:00:00.000Z",
  "updatedAt": "2026-10-24T01:00:00.000Z",
  "deviceId": "<opaque string, the device that wrote this version>"
}
```

- Base64 is standard (RFC 4648 §4, `+/`, with `=` padding).
- `version` must be `1`. A reader rejects a higher version.
- `kdf` and `cipher` must be exactly the strings above.
- `iterations`: writers use **600,000**. Readers accept 1,000 to 10,000,000
  (1,000 exists only for the test vectors; never write it).
- `salt` decodes to 16 bytes, `nonce` to 12 bytes.
- `createdAt` / `updatedAt`: ISO-8601 UTC. `createdAt` is kept from the first
  save; `updatedAt` is the time of this write.
- Readers must not re-serialize the header for the AAD: use the stored bytes.
  Writers may order keys freely, since the AAD is whatever bytes they wrote.

## Key derivation

```
key = PBKDF2(HMAC-SHA256, password = UTF-8(NFC(passphrase)), salt, iterations, dkLen = 32 bytes)
```

The passphrase is **Unicode NFC normalized**, then UTF-8 encoded
(`new TextEncoder().encode(passphrase.normalize('NFC'))` in JS). Different
keyboards produce "é" as one code point or as "e" plus a combining accent; NFC
makes both derive the same key. `test/vault/vectors/nfd_passphrase.json`
checks this.

## Encryption

```
AES-256-GCM(key, iv = nonce (12 bytes), additionalData = AAD, tagLength = 128)
```

A writer generates a **fresh random nonce on every save** (never reuse a nonce
with the same key). It may keep the salt and derived key for the session, or
pick a new salt (the app picks a new salt on every unlock and on a passphrase
change).

A wrong passphrase and a modified file both make AES-GCM fail; they can't be
told apart, and that is intended.

## Plaintext

UTF-8 JSON, identical to the app's JSON backup export
(`BackupService.buildJson`):

```json
{
  "format": "life-manager-backup",
  "version": 1,
  "exportedAt": "…",
  "counts": {"items": 3, "history": 0},
  "items":   [ { "uuid": "…", "kind": "task", "title": "…", "updated_at": "…", "is_deleted": false, … } ],
  "history": [ … ]
}
```

Merge rules (what the app does on open, and what a web editor must do too):
items are last-write-wins on `updated_at`; deleted items stay as tombstones
(`is_deleted: true`) and must not be dropped; history entries are insert-only,
keyed by `uuid`. An editor that changes an item must set its `updated_at` to
the current UTC time.

## WebCrypto decrypt (reference)

```js
const b64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

async function openVault(bytes /* Uint8Array */, passphrase) {
  if (new TextDecoder().decode(bytes.slice(0, 4)) !== 'LMV1') throw new Error('Not a vault');
  const h = new DataView(bytes.buffer, bytes.byteOffset).getUint32(4, false);
  const aad = bytes.slice(0, 8 + h);
  const header = JSON.parse(new TextDecoder().decode(bytes.slice(8, 8 + h)));
  const base = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(passphrase.normalize('NFC')), 'PBKDF2', false, ['deriveKey']);
  const key = await crypto.subtle.deriveKey(
    { name: 'PBKDF2', hash: 'SHA-256', salt: b64(header.salt), iterations: header.iterations },
    base, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
  const plain = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: b64(header.nonce), additionalData: aad, tagLength: 128 },
    key, bytes.slice(8 + h));
  return { header, key, data: JSON.parse(new TextDecoder().decode(plain)) };
}
```

To write: build the header JSON with a new random 12-byte nonce
(`crypto.getRandomValues`) and the current `updatedAt`, assemble
`LMV1 || uint32BE(len) || headerBytes`, encrypt the UTF-8 plaintext with that
block as `additionalData`, and append the result.

## Test vectors

Each `test/vault/vectors/*.json` holds: `passphrase` (`nfd_passphrase.json`
also has `passphraseNfc`), `iterations` (1000, for
speed only), `salt` and `nonce` (base64), `headerJson` (the exact header bytes
as a string), `plaintext`, `derivedKey` (base64, 32 bytes) and `file` (base64
of the whole vault). An implementation is correct if it derives `derivedKey`,
decrypts `file` to `plaintext`, and, given the same header bytes, salt, nonce
and plaintext, produces `file` byte for byte.
