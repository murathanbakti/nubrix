# Plan: Vitrin encryption at rest

Status: plan, 2026-11-03. Decision source: [research/vitrin-encryption.md](../research/vitrin-encryption.md) (its Recommendation is the decision). Branch `murathan.bakti/vitrin-encryption-a12a14`.

Summary: AES-GCM (CryptoKit) per field and per image file; one 256-bit master key in the file-based login keychain (Release) or a 0600 file (Debug); HMAC dedup hash; FTS5 removed and replaced by an in-memory `memmem` index; resumable in-place migration to schema v3. No on/off switch.

## New types

### `ClipCipher` (`Nubrix/Features/Clipboard/ClipCipher.swift`)

```swift
enum ClipCipherError: Error { case malformed, unsupportedVersion, authenticationFailed }

struct ClipCipher: @unchecked Sendable {
    static let formatVersion: UInt8 = 1
    static func makeMasterKey() -> SymmetricKey            // 256-bit random
    init(masterKey: SymmetricKey)                          // HKDF<SHA256>, empty salt:
                                                           //   enc = info "nubrix.vitrin.enc.v1", 32 bytes
                                                           //   mac = info "nubrix.vitrin.mac.v1", 32 bytes
    let keyID: String                                      // hex of first 16 bytes of HMAC(mac, "key-id")
    func seal(_ plaintext: Data, aad: String) throws -> Data   // [0x01] + AES.GCM combined (nonce|ct|tag)
    func open(_ sealed: Data, aad: String) throws -> Data      // throws, never traps
    func sealString(_ s: String, aad: String) throws -> Data
    func openString(_ d: Data, aad: String) throws -> String
    func keyedHash(_ data: Data) -> String                 // hex HMAC-SHA256(mac, data)
    func keyedHash(text: String) -> String                 // keyedHash(Data(text.utf8))
}
```

AAD strings (`ClipCipher.aad...` helpers): row fields `"v1|content|<hash>"`, `"v1|preview|<hash>"`, `"v1|source|<hash>"`; files `"v1|img|<file name>"` (the thumbnail uses its own file name).

### `VitrinKeyStore` (`Nubrix/Features/Clipboard/VitrinKeyStore.swift`)

```swift
enum VitrinKeyLoad { case ready(SymmetricKey), missing, invalid, locked(OSStatus) }

protocol VitrinKeyProviding: Sendable {
    var label: String { get }                 // "login keychain" / "Debug key file"
    func load() -> VitrinKeyLoad
    func create(_ key: SymmetricKey) -> OSStatus   // errSecDuplicateItem allowed
    func delete() -> OSStatus                       // errSecItemNotFound counts as success
}

struct KeychainVitrinKeyStore: VitrinKeyProviding  // service "dev.nubrix.vitrin", account "history-key.v1",
                                                   // kSecAttrLabel "Nubrix Vitrin history key",
                                                   // kSecUseDataProtectionKeychain: false (explicit),
                                                   // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, never synchronizable.
                                                   // errSecItemNotFound -> .missing; wrong length -> .invalid;
                                                   // any other status (-25293 Deny, -128 cancel, -25308 locked, ...) -> .locked(status)
#if DEBUG
struct FileVitrinKeyStore: VitrinKeyProviding      // 32 raw bytes in a 0600 file; ENOENT -> .missing; wrong length -> .invalid;
                                                   // other read errors -> .locked(errSecIO)
#endif

enum VitrinKeyStores {
    static func makeDefault(directory: URL) -> VitrinKeyProviding  // DEBUG: FileVitrinKeyStore(directory/"key"), else Keychain
}
```

`ClipStore.defaultDirectory` becomes `.../Nubrix/Vitrin-Debug` under `#if DEBUG` and stays `.../Nubrix/Vitrin` in Release. A Debug build therefore never reads, prompts for or wipes the Release key or DB, whether or not Debug gets its own bundle id (and container) from the permissions work.

### `ClipVault` (`Nubrix/Features/Clipboard/ClipVault.swift`): key bootstrap, pure and testable

```swift
enum ClipVaultOpenResult { case ready(ClipDatabase, wasReset: Bool), locked(OSStatus), failed(String) }

enum ClipVault {
    static func open(directory: URL, keys: VitrinKeyProviding) -> ClipVaultOpenResult
    static func reset(directory: URL, keys: VitrinKeyProviding) -> ClipVaultOpenResult  // "Reset history and key"
    static func wipeFiles(in directory: URL)   // vitrin.sqlite, -wal, -shm, *.png, *.vimg (never other files)
}
```

`open` state machine (runs on `ClipStore.queue`; the keychain prompt blocks that thread, never main):

1. `ClipDatabase(directory:)` opens and runs the schema step (no key needed). Read `storedKeyID` (meta `key_id`), `encryptedRowCount` (`enc = 1`) and `count()`.
2. `keys.load()`:
   - `.locked(status)` → close DB, return `.locked(status)`. Nothing is written or deleted.
   - `.ready(key)`: cipher = `ClipCipher(key)`. If `storedKeyID == cipher.keyID` → ready. If `storedKeyID == nil` and `encryptedRowCount == 0` → write key_id, ready (first run or v2 DB to migrate). Otherwise (mismatch, or encrypted rows without key_id) → **lost**: close, `wipeFiles`, reopen, write key_id, `wasReset = count > 0`.
   - `.missing` / `.invalid`: (`invalid` first deletes the item.) If `storedKeyID != nil || encryptedRowCount > 0` → **lost**: wipe as above. Create a new key with `keys.create`; `errSecDuplicateItem` → `load()` again once; any other failure → `.locked(status)` (the wipe already happened only when the key was provably gone). Write key_id. `wasReset = (lost && count > 0)`.
3. `db.install(cipher)` before the DB is handed out. `ClipDatabase` without a cipher refuses reads and writes of encrypted data (throws / returns nil).

`reset`: wipe files, `keys.delete()`, then `open` (creates a new key). Works from the locked state too, because it never needs the old key (crypto-shredding of remnants).

### `ClipImageVault` (in `ClipVault.swift`)

`struct ClipImageVault: Sendable { let directory: URL; let cipher: ClipCipher }` with
`write(_ data: Data, named:) throws` (seal with `"v1|img|<name>"`, `.atomic`, 0600) and `read(named:) -> Data?` (`.vimg` → decrypt, `.png` → raw bytes for not-yet-migrated rows, failure → nil). It touches only files, so `ClipStore` can use it on the thumbnail/preview queues and in drag/copy callbacks without the database queue.

### `ClipSearchIndex` (`Nubrix/Features/Clipboard/ClipSearchIndex.swift`)

```swift
final class ClipSearchIndex {          // confined to ClipStore.queue (owned by ClipDatabase)
    static let maxBytesPerItem = 65_536
    static func fold(_ s: String) -> [UInt8]   // folding([.caseInsensitive, .diacriticInsensitive], locale: nil), UTF-8, cut at maxBytesPerItem
    func insert(id: Int64, used: Double, text: String)
    func touch(id: Int64, used: Double)
    func remove(id: Int64)
    var count: Int
    func search(_ raw: String, limit: Int) -> [Int64]   // whitespace tokens, each folded, all must memmem-match (AND);
                                                       // ordered used DESC, id DESC; empty query -> []
}
```

Behaviour change (documented): substring match, not token prefix ("vit" finds "invitation"); text past the first 64 KB of an item is not searched. Images never match (as with FTS, which indexed '').

## `ClipDatabase` changes

- `schemaVersion = 3`. `init(directory:)` adds `PRAGMA temp_store=MEMORY`; keeps WAL, `secure_delete=ON`, `synchronous=NORMAL`.
- Schema step (`migrate()`, every open, no key): `CREATE TABLE` gains `enc INTEGER NOT NULL DEFAULT 0, content_enc BLOB, preview_enc BLOB, source_enc BLOB`; `ALTER TABLE ADD COLUMN` for each when missing; `CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v BLOB)`. FTS table and triggers are **no longer created**. A brand-new DB sets `user_version = 3` directly.
- `install(_ cipher:)`, `var imageVault: ClipImageVault?`, `storedKeyID`, `setKeyID(_:)`, `encryptedRowCount`, `plaintextRowCount`, `close()` (sqlite3_close_v2, later calls fail cleanly).
- `bind` learns `Data` (`sqlite3_bind_blob`); a `blob(stmt, col)` reader.
- `insert(...)`: requires cipher, writes `enc = 1`, `content/preview/source = NULL`, `*_enc` sealed with the row hash in the AAD. `preview`, `text_len` and `bytes` are computed from plaintext as today. Updates the search index if it exists.
- Reading: `columns` adds `enc, preview_enc, source_enc, hash`; `row()` becomes an instance method that decrypts when `enc = 1` (failure → `preview = nil`, `sourceApp = nil`, no crash) and uses the plaintext columns when `enc = 0`.
- `fullText(id:maxChars:)`: decrypt (or plaintext for `enc = 0`), then prefix in Swift by Unicode scalars (same unit as the old SQL `substr`).
- `hash` helpers: `textHash(_:)`, `imageHash(_ png: Data)` via `cipher.keyedHash`.
- `writeImage(png:thumbnail:)` → `UUID.vimg` + `UUID.thumb.vimg` through the image vault. `thumbnailName(for:)` → `base + ".thumb." + ext` (keeps `.thumb.png` for old rows, gives `.thumb.vimg` for new). `imageData(named:)` → vault read.
- `search(_:limit:)`: empty query → `summaries(limit:)`; otherwise build the index on first use (decrypt every non-image row), get ids, fetch summaries for those ids, keep the index order. `dropSearchIndex()`. `touch` updates the index; `delete(id:)` removes; `expire`/`trim`/`clear` drop the index when they removed rows.
- `ftsQuery`, `ensureFTSSecureDelete` and the FTS rebuild are removed.
- `sweepOrphans()`: list the directory; delete `*.png` / `*.vimg` files not referenced by any `image_file` or its thumbnail name. Never touches other files (the Debug `key` file lives there).

### Migration (v2 → v3)

`runDeferredMigration()` (on the queue, after the key is ready):
1. `user_version < 1`: `UPDATE clips SET preview = substr(content,1,300), text_len = length(content) WHERE content IS NOT NULL AND preview IS NULL` (no FTS rebuild).
2. `user_version < 2`: `backfillBytes()` as today.
3. `user_version < 3`: `DROP TRIGGER IF EXISTS clips_ai`, `DROP TRIGGER IF EXISTS clips_ad`, `DROP TABLE IF EXISTS clips_fts`. Dropping them first is required: the external-content delete trigger would feed FTS the wrong (NULL) content once rows are encrypted, and the new search never uses FTS.
4. `sweepOrphans()` (every start, also for v3).

`migrateEncryptionBatch(limit: 200) throws -> Bool` (true = more `enc = 0` rows remain); `ClipStore` re-enqueues it batch by batch so captures interleave and are never blocked behind the whole migration:
1. `SELECT id, kind, content, preview, source, image_file, pinned, used, created FROM clips WHERE enc = 0 ORDER BY id LIMIT 200`.
2. For each image row: read `X.png` / `X.thumb.png`; missing main file → mark the row for deletion; else write `X.vimg` / `X.thumb.vimg` (atomic, 0600) **before** the transaction. New hash = HMAC over the PNG bytes; text rows: HMAC over `content`.
3. `BEGIN IMMEDIATE`. For each row: if another row already has the new hash (a capture since start re-inserted the same text), merge: `UPDATE` the survivor with `pinned = max`, `used = max`, `created = min`, then `DELETE` the old row. Otherwise `UPDATE clips SET hash=?, enc=1, content_enc=?, preview_enc=?, source_enc=?, content=NULL, preview=NULL, source=NULL, image_file=? WHERE id=?`. `COMMIT`.
4. After `COMMIT`: delete the old PNGs (and files of merged/deleted rows). On any error: `ROLLBACK`, delete the `.vimg` files written for this batch, log, return/throw. A crash anywhere leaves either untouched rows (redone next start) or orphan files (removed by `sweepOrphans`).
5. Test hook: `var migrationFault: ((ClipMigrationFaultPoint) throws -> Void)?` with points `.beforeCommit` and `.afterCommit` (internal, nil in the app).

`finishEncryptionMigration()` when no `enc = 0` row is left and `user_version < 3`: `VACUUM`, `wal_checkpoint(TRUNCATE)`, `user_version = 3`. Failures are logged and retried at the next start; capture continues on mixed rows meanwhile.

## Other changes

- `ClipImageProcessor`: drop `textHash` and `PreparedClipImage.hash` (and the CryptoKit import). Hashes need the key and are computed on the store queue.
- `ClipImageLoader`: `downsample(data:maxPixel:)` (`CGImageSourceCreateWithData`) and `downsample(load: @Sendable () -> Data?, maxPixel:, on:)` with the same cancellation flag; the URL variants go.
- `ClipItem.thumbnailFile` keeps calling `ClipDatabase.thumbnailName(for:)` (now extension-aware).
- `ClipboardMonitor.capture`: calls `ClipStore.shared.addText(classified, source:)` without a hash.
- `ClipStore`:
  - `enum VitrinVaultState: Equatable { case off, opening, ready, locked(OSStatus), failed(String) }`, `@Published private(set) var vaultState`. `isReady` = `.ready`.
  - `start(directory:keys:)`: state `.opening`, run `ClipVault.open` on `queue`, a generation counter ignores results after `shutdown()`. On ready: install database, set `Defaults[.vitrinKeyResetNotice] = true` when `wasReset`, enqueue `runDeferredMigration`, then the batch loop, then `finishEncryptionMigration`, `sweep(reloadAlways: true)`, start the hourly timer.
  - `retryUnlock()` (manual Retry), `retryIfKeychainLocked()` (automatic, only for `errSecInteractionNotAllowed`, so a Deny is not re-prompted on every unlock), `resetHistoryAndKey()` (close DB on the queue, `ClipVault.reset`, then the same ready path; clears caches and the reset notice).
  - `addText(_:source:)`: hash computed on the queue via `db.textHash`; the `lastTextHash` shortcut keeps working with that hash. `addImage`: hash via `db.imageHash(image.png)`.
  - `search`: through `db.search`; schedules a 60 s idle drop of the index (main-actor timer → `enqueue { $0.dropSearchIndex() }`). `dropSearchIndex()` public; `shutdown()` drops it with the DB.
  - `thumbnail`/`previewImage`: `ClipImageLoader.downsample(load: { vault.read(named:) } ...)`. `copy` of images and `itemProvider` decrypt through the vault. `namedDragCopy(data:named:root:cleanupAfter:)` writes the decrypted PNG (0600, 0700 folder, 300 s cleanup).
- `VitrinPanelController.close()` calls `ClipStore.shared.dropSearchIndex()`.
- `VitrinService`: observes `ClipStore.shared.$vaultState` → `ScreenshotWatcher.shared.refresh()` when it changes (the watcher checks `isReady`, which now turns true asynchronously); `NSWorkspace.sessionDidBecomeActiveNotification` and distributed `com.apple.screenIsUnlocked` → `retryIfKeychainLocked()`; distributed `com.apple.screenIsLocked` → `dropSearchIndex()`.
- `VitrinDefaults`: `vitrinKeyResetNotice: Bool = false`.
- `VitrinSettings`: a "Storage" section at the top of the enabled sections: status row ("Encrypted, key in your login keychain" / "Encrypted, Debug key file" / "Opening…" / "Locked: Keychain access denied" or "Locked: keychain is locked" + **Retry** / "Could not open history" + **Retry**), the one-time reset notice with an OK button, and **Reset history and key…** (destructive, confirmation: "Deletes all Vitrin items, including pinned ones, and creates a new encryption key."). **Clear history** keeps its meaning.
- `VitrinTabView` (notch): when locked/failed show `VitrinEmptyState("Vitrin is locked", "Allow keychain access in Settings, Vitrin.")`; show the reset notice line once (dismiss clears the default).
- Docs: `PRIVACY-AND-SECURITY.md` Vitrin section (what is encrypted, what is not: kind, sizes, timestamps, pin state, count, drag copies, pasteboard, screenshot originals, running memory; keychain prompt when switching between a local Apple Development build and a Developer ID release; Deny → locked; WAL/APFS/SSD deletion limits; Reset as crypto-shredding), `TROUBLESHOOTING.md` (locked Vitrin, Always Allow, reset notice), `ROADMAP.md` (encryption line done).

No entitlement, `project.pbxproj` or signing change. Files in `NubrixTests/` join the synchronized group automatically.

## Tests (`NubrixTests/Vitrin/`, XCTest, temp directories, injected keys, never the real Keychain item)

Helpers: `MemoryKeyStore` (configurable `.ready/.missing/.locked`, records calls), `VitrinV2Fixture` (builds a v2 DB with the old schema SQL, FTS5 table + triggers, plaintext rows and real PNG + thumbnail files), `rawBytesContain(marker, in: directory)` scanning `vitrin.sqlite`, `-wal`, `-shm` and every file.

1. `ClipCipherTests`: round trip; tampered byte, wrong AAD, wrong key, truncated data, wrong version byte → throws; HMAC is deterministic per key, differs across keys; keyID stable per key.
2. `ClipSearchIndexTests`: AND tokens, case and diacritic folding (`"Çay"` ↔ `"cay"`, `"İstanbul"` ↔ `"istanbul"`), substring semantics, recency order and limit, insert/remove/touch.
3. `ClipDatabaseEncryptionTests`: insert/read round trip of text, link, image (thumbnail and preview decode from `.vimg` via `ClipImageLoader.downsample(data:)`); dedup of the same text → one row; marker string and marker image bytes never in raw files after insert + checkpoint; `fullText(maxChars:)`; retention `expire`, `trim(maxUnpinned:)`, `trim(maxBytes:)` and pinned rows survive; `delete` removes `.vimg` files; `sweepOrphans` removes unreferenced images only and keeps a `key` file.
4. `ClipMigrationTests`: v2 fixture → v3: all `enc = 1`, `clips_fts` and triggers gone, PNGs gone, `.vimg` present, previews/full text/sources/pins/sizes equal to the fixture, marker absent from raw files, `user_version = 3`; crash simulation with the fault hook at `.beforeCommit` and `.afterCommit` after batch 1 (batch size 2), then reopen + finish → identical result, no orphans; merge when a re-captured duplicate exists; search parity: for a query set, the old FTS result ids (queried on the fixture before migration) are a subset of the new index result ids, and the listed extra substring matches are exactly the expected ones.
5. `ClipVaultTests`: fresh dir + missing key → created, ready, not reset; reopen → same key_id; `.locked` with encrypted data → `.locked`, files untouched byte-for-byte, key store not asked to create or delete; missing key with encrypted rows → wiped, new key, `wasReset`; key mismatch → wiped, `wasReset`; `.invalid` → item deleted and recreated; `reset` from locked → fresh empty DB and new key; v2 DB + missing key → key created, no wipe, rows kept.

Run: `scripts/run-tests.sh ~/Library/Caches/Nubrix/DerivedData-vitrin-encryption`.

## Implementation slices (Sonnet subagents, review + build between)

1. `ClipCipher`, `VitrinKeyStore`, `ClipSearchIndex` (pure, no callers yet).
2. `ClipDatabase`, `ClipVault`/`ClipImageVault`, `ClipImageLoader`, `ClipImageProcessor`, `ClipItem`, `ClipStore`, `ClipboardMonitor` (data path compiles and runs end to end).
3. `VitrinDefaults`, `VitrinSettings`, `VitrinTabView`, `VitrinService`, panel close hook.
4. Tests (above). 5. Docs (in parallel with 4).

## On-device checks (the user, later)

- First Release run with existing history: one keychain item "Nubrix Vitrin history key" appears in Keychain Access (login); no prompt for a Developer ID build that created it; history still there after migration; `vitrin.sqlite` has no readable text (`strings vitrin.sqlite | grep <something you copied>` finds nothing), only `.vimg` files beside it.
- Switching between a local Apple Development install and a Developer ID release: one prompt per direction; "Always Allow" silences it.
- Deny at the prompt → Settings, Vitrin shows Locked + Retry, history intact; Retry → prompt again → Allow → history back.
- Delete the item in Keychain Access, relaunch → history reset, one-time notice.
- Reset history and key → empty history, new item.
- Debug build: uses `Vitrin-Debug/`, never prompts, the Release history is untouched.

## Risks

- A keychain prompt on the store queue blocks capture until answered (captures are queued, not lost; the monitor skips while `isReady` is false).
- `errSecItemNotFound` must really mean "gone": a different keychain search list or a broken login keychain could look like a lost key and wipe history. Mitigated only by the explicit service/account query; documented.
- VACUUM of a 1 GiB history at the end of migration takes time and double disk space briefly; it runs once, off the main thread, and is retried if it fails.
- Substring search over 64 KB per item is a behaviour change from FTS prefix search.
