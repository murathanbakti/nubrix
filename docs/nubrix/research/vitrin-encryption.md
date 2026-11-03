# Research: encrypting Vitrin history on disk

Status: research note, 2026-11-03. No code changed. Decision requested: see [Recommendation](#recommendation).

## Where we are

- `Nubrix/Features/Clipboard/ClipDatabase.swift` (system `SQLite3`, `schemaVersion = 2`) stores everything in `~/Library/Containers/dev.nubrix.app/Data/Library/Application Support/Nubrix/Vitrin/vitrin.sqlite` (`ClipStore.defaultDirectory`). The directory is 0700, the files are 0600, and it is excluded from backup (`excludeFromBackup`).
- Table `clips`: `kind, content, preview (first 300 scalars), text_len, image_file, image_w, image_h, hash, source, created, used, pinned, bytes`. Unique index on `hash`, and indexes on `used` and `(pinned, used, id)`.
- Search uses `clips_fts` (FTS5, external content `content='clips'`, `unicode61 remove_diacritics 2`) and is kept in sync by the `clips_ai`/`clips_ad` triggers. `ftsQuery` turns each whitespace token into `"tok"*` (prefix AND). `search()` joins on the FTS table, orders by `used DESC` and returns 300 rows (`ClipStore.searchLimit`). The FTS5 table holds a full plaintext copy of every text in its `_data` b-tree.
- Pragmas: `journal_mode=WAL`, `secure_delete=ON`, `synchronous=NORMAL`, FTS5 `secure-delete=1` (`ensureFTSSecureDelete`). `checkpoint()` runs `wal_checkpoint(TRUNCATE)` after deletes. `temp_store` is not set.
- Images: `writeImage` writes `UUID.png` and `UUID.thumb.png` (plaintext PNGs, `.atomic`, 0600) next to the DB. They are read by `ClipImageLoader.downsample(url:)` (`CGImageSourceCreateWithURL`), `ClipStore.copy` (`Data(contentsOf:)`), and `ClipStore.itemProvider`, which uses `namedDragCopy` to make a plaintext copy in `$TMPDIR/NubrixDrag/<uuid>/` that is deleted after 300 s.
- Dedup hash: `ClipImageProcessor.textHash` and `PreparedClipImage.hash` are **unkeyed SHA-256** of the plaintext. Whoever has the DB can confirm a guess ("is this phone number or password in the history?").
- Screenshots: `ScreenshotWatcher.importFile` reads the user's screenshot folder and goes through `addImage`. The originals stay where macOS saved them, which is out of scope.
- Limits: text ≤ 256,000 UTF-16 units (`ClipClassifier.maxTextLength`), image ≤ 25 MB, 2000 unpinned items, 1 GiB total (`ClipStore.maxTotalBytes`), list of 1000.
- Signing: Debug and Release both use `CODE_SIGN_IDENTITY[sdk=macosx*] = "-"` (`project.pbxproj`). `scripts/install-local.sh` re-signs Release with the first "Apple Development" identity (the installed app's DR is `identifier "dev.nubrix.app" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: … (VFPKZZUY7T)" …`). Releases are signed with Developer ID, team `399MAAJ7QT` (`scripts/sign-release.sh`, `scripts/install.sh`). Deployment target is macOS 14.0, and the app is sandboxed (both `.entitlements` files) with no keychain or application-identifier entitlements and no provisioning profile.
- The existing Keychain user `Nubrix/Features/GitHub/GitHubTokenStore.swift` uses SecItem **without** `kSecUseDataProtectionKeychain`, so it uses the file-based login keychain.
- There is no XCTest target in `Nubrix.xcodeproj`.

## Threat model (be honest)

Encryption protects:
- copies of the Vitrin folder (support zips, `rsync`/Backblaze/clone tools that ignore `isExcludedFromBackup`, a copied user folder, a disk image of an unlocked volume);
- processes that can read the container but cannot read the key without a prompt. Since macOS 14, reading another app's container triggers the "access data from other apps" prompt unless the process has Full Disk Access. FDA processes (terminals, backup tools, malware riding on them) currently read Vitrin silently. With a Keychain key they get the DB and ciphertext but still hit a keychain prompt for the key;
- data that was deleted earlier, once the key is destroyed ("crypto-shredding" on Reset), because remnants in free SQLite pages, the WAL or SSD blocks become ciphertext without a key.

It does **not** protect: the running app's memory, a logged-in Mac with the user away, a user who clicks "Always Allow" for a malicious tool, metadata left in clear (kind, sizes, timestamps, pin state, item count), the drag temp copies, the pasteboard itself, or screenshot originals. FileVault (on by default from macOS 26.4) already covers a powered-off stolen Mac ([Apple Platform Security, Data Protection](https://support.apple.com/guide/security/data-protection-overview-secf6276da8a/web)). The PRIVACY doc should say exactly this.

## 1. Key management

**Cipher:** CryptoKit `AES.GCM` with a 256-bit `SymmetricKey`, using `sealedBox.combined` (12-byte random nonce + ciphertext + 16-byte tag). The CPU has hardware AES on Apple silicon and AES-NI on Intel. Random 96-bit nonces stay safe far beyond Vitrin's volume (NIST caps a key at 2³² random-nonce messages, [SP 800-38D](https://csrc.nist.gov/pubs/sp/800/38/d/final)). `ChaChaPoly` would work just as well, but AES-GCM is the platform default ([CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)). Derive two subkeys with `HKDF<SHA256>`: `enc` (info `nubrix.vitrin.enc.v1`) and `mac` (info `nubrix.vitrin.mac.v1`, for the keyed dedup hash). Store only the 32-byte master key.

Measured on this Mac (M4 Max, `swiftc -O`, 5000 synthetic items / 5.4 MB of text): seal all 11 ms, open all 12 ms, open 1000 previews 1.5 ms, seal or open a 25 MB image 6–8 ms. Crypto cost is negligible. Expect 3–5× slower on older Intel Macs.

**Where the key lives: two Keychain implementations** ([TN3137 On Mac keychain APIs and implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)):

| | File-based (login) keychain | Data protection keychain (`kSecUseDataProtectionKeychain = true`) |
|---|---|---|
| Access control | ACL that holds the **designated requirement (DR)** of the app that created the item | Keychain access groups taken from entitlements |
| Entitlements and profile | None. It already works for `GitHubTokenStore` in the sandboxed app | `com.apple.application-identifier` + `keychain-access-groups` (`399MAAJ7QT.dev.nubrix.app`). These are restricted entitlements: "must be authorized by a provisioning profile" (TN3137), embedded as `Contents/embedded.provisionprofile` ([TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles), [keychain-access-groups](https://developer.apple.com/documentation/bundleresources/entitlements/keychain-access-groups)). Quinn: the DP keychain "is available to directly distributed programs that use Developer ID signing", but "that access must be authorised by a provisioning profile" ([forum 826107](https://developer.apple.com/forums/thread/826107)). Without the entitlement you get `errSecMissingEntitlement` (-34018) ([forum 114456](https://developer.apple.com/forums/thread/114456)) |
| Developer ID release → next release | Same DR (team OU + Developer ID anchor), so **no prompt** | No prompt |
| Apple Development local install ↔ Developer ID release | Different DRs (leaf CN vs Developer ID OID + OU), so **one prompt** per direction. "Always Allow" adds that app to the ACL, after which both are trusted ([forum 98484](https://developer.apple.com/forums/thread/98484), [forum 732869](https://developer.apple.com/forums/thread/732869)) | No prompt if both builds carry a profile for the same App ID |
| Ad-hoc (`-`) Debug build | DR is the cdhash, so it **prompts after every rebuild** | Not possible: restricted entitlements without a profile cause the app to be killed at launch |
| Future | "On the road to deprecation", but not deprecated (TN3137) | Apple's recommended target |

The DP keychain is the cleaner end state. It needs an App ID, a Developer ID provisioning profile and a Mac development profile, profile secrets in the `release` environment, `sign-release.sh` embedding the profile, and Debug and contributor builds that keep working without those entitlements. That is a supply-chain change for an open-source repo where contributors build ad-hoc. The file-based keychain needs **no signing or entitlement change** and matches `GitHubTokenStore`. Its only cost is one "Always Allow" when switching between a local Apple Development build and a Developer ID release.

**Key item:** `kSecClassGenericPassword`, service `dev.nubrix.vitrin`, account `history-key.v1`, `kSecAttrLabel` "Nubrix Vitrin history key" (shown in the prompt), `kSecUseDataProtectionKeychain: false` set explicitly so that a later move to the DP keychain is a deliberate migration. Create it with `SecItemAdd` only when the DB holds no encrypted rows.

**Key states. Never crash; only wipe when the key is provably gone:**
- `errSecSuccess`, and the key matches the DB's `meta.key_id` (first 16 bytes of HMAC(mac, "key-id")): ready.
- `errSecItemNotFound` while the DB has encrypted rows, or `key_id` mismatch: **key lost**. Wipe rows and `.vimg` files, create a new key, start fresh, and show a one-time banner: "Vitrin history was reset because its encryption key is no longer in your keychain."
- `errSecAuthFailed` (-25293, the user clicked Deny), `errSecUserCanceled`, `errSecInteractionNotAllowed` (keychain locked) or any other error: **locked**. Do *not* wipe. The store stays in a `locked` state: no capture, no list, and Settings shows "Locked: Keychain access denied" with Retry and Reset history. Retry again on the next unlock or session activation.
- Debug: the same bundle ID means the **same container** as Release. An ad-hoc Debug build must neither prompt on every run nor wipe the real history. Under `#if DEBUG` use a file key provider (`Vitrin-Debug/key`, 0600) and the separate directory `Vitrin-Debug/`. Debug then never touches the Release key or DB.

## 2. What to encrypt and how search works

| Data | Decision |
|---|---|
| `content`, `preview` | Encrypt as separate BLOBs (`content_enc`, `preview_enc`). The list only decrypts 300-char previews, never 256 K texts |
| `source` (bundle id) | Encrypt (`source_enc`). It shows which apps you copy from, costs almost nothing, and `isScreenshot` and the filters already work on decrypted `ClipItem`s in memory |
| `hash` | Replace with HMAC-SHA256(mac, plaintext) hex. The unique index and dedup still work, and guesses can no longer be confirmed |
| Images + thumbnails | Encrypt the whole file → `UUID.vimg`, `UUID.thumb.vimg`. Decrypt into `Data` and use `CGImageSourceCreateWithData` |
| `kind, text_len, image_w/h, bytes, created, used, pinned` | Leave in clear. SQL needs them for ordering, retention (`expire`), `trim(maxUnpinned:)` and `trim(maxBytes:)`. Document the leak |
| Drag copy (`namedDragCopy`) | Has to stay plaintext so the receiving app can read it. Keep the 300 s cleanup and the 0700 folder; note it in the PRIVACY doc |

AAD: `"v1|<column>|<hmac hash>"` for row fields and `"v1|img|<file name>"` for files. This binds each ciphertext to its row or file, so blobs can't be swapped.

**Search options**
1. *In-memory index over decrypted rows*: **recommended**. On the first search, decrypt every row's content into one array of folded UTF-8 byte buffers: `folding([.caseInsensitive, .diacriticInsensitive])`, at most 64 KB per item (the same as `ClipInsightAnalyzer.maxAnalyzedLength`). Match every query token with `memmem` (AND) and order by `used DESC`, limit 300. Measured with 5000 items: building the index (decrypt + fold) takes about 72 ms, and a query takes **0.6–2.8 ms** (a miss is the worst case). Plain Swift `String.contains` took 13–92 ms and `range(of:options:)` 58–450 ms, so use `memmem`. Memory is about 5–6 MB for 5000 typical items; the pathological worst case is about 128 MB (2000 × 64 KB). Drop the index when the panel closes, after 60 s idle, on `com.apple.screenIsLocked`, and in `shutdown()`. Update it incrementally on insert and delete while it lives. Behaviour change: matching is a substring (`"vit"` finds "invitation"), not a token prefix. That is arguably better for a clipboard, and results stay ordered by recency as they are today.
2. *Keyed-hash token index* (blind index: `clip_tokens(hmac BLOB, id)`): only exact tokens. Prefix search needs every prefix indexed (many times the size), and it leaks token frequency and co-occurrence. Rejected.
3. *Encrypted FTS*: the system SQLite has no codec. SQLCipher would bring a second SQLite plus a crypto backend into the bundle (`verify-bundle.sh` allowlist, `SUPPLY-CHAIN.md`), which is not justified for at most a few thousand rows. A custom encrypting VFS on the system library (`sqlite3_vfs_register` + `SQLITE_FCNTL_RESERVE_BYTES` for nonce and tag) would keep FTS but means hand-written page crypto for the DB *and* WAL. That is high risk. Rejected.

## 3. Migration (schema v3)

Done in place, row by row, so it can be resumed. It runs from `runDeferredMigration()` on `ClipStore.queue` after the key is ready:
1. `ALTER TABLE clips ADD COLUMN enc INTEGER NOT NULL DEFAULT 0` (0 = plaintext, 1 = AES-GCM v1), plus `content_enc BLOB`, `preview_enc BLOB` and `source_enc BLOB`. Create `meta(k TEXT PRIMARY KEY, v BLOB)` with `key_id`. All new inserts write `enc = 1`. Readers handle both states while the migration runs.
2. Batches of 200 rows `WHERE enc = 0`, one transaction each. For images, first write `UUID.vimg` / `.thumb.vimg` atomically (0600). Then, in the transaction, set the new columns and the new HMAC `hash`, set `image_file` to the new name, set `content = preview = source = NULL` and `enc = 1`. After `COMMIT`, delete the old PNGs. A crash at any point leaves either an untouched row (redo it) or orphan files.
3. **Orphan sweep** at every start: delete any file in the directory that is not `vitrin.sqlite*` and not referenced by `image_file` or its thumbnail. This also cleans up crashes from today's code.
4. When no `enc = 0` row is left: `DROP TRIGGER clips_ai`, `DROP TRIGGER clips_ad`, `DROP TABLE clips_fts`, then `VACUUM`, `wal_checkpoint(TRUNCATE)`, `PRAGMA user_version = 3`. If the migration fails (disk full, for example), log it, stay on mixed rows, and retry at the next start. Never block capture.
5. Hash collisions during re-keying cannot happen, since the plaintext is unique per row and the HMAC is injective in practice.

**Secure delete limits.** `secure_delete=ON` zeroes freed SQLite pages, but in WAL mode the old content stays in the `-wal` file until a checkpoint truncates it ([PRAGMA secure_delete](https://www.sqlite.org/pragma.html#pragma_secure_delete), [antonz](https://antonz.org/sqlite-secure-delete/)). FTS5 needs its own `secure-delete` option ([FTS5](https://www.sqlite.org/fts5.html#the_secure_delete_configuration_option)). Neither SQLite zeroing nor deleting the PNGs reaches the physical NAND: APFS is copy-on-write and the SSD remaps blocks (wear levelling, TRIM), so old plaintext can survive on the device until garbage collection, and only someone with raw block access to an unlocked or non-FileVault volume could read it. The honest wording for users: "After the upgrade, old unencrypted copies are deleted. Your Mac's storage may keep remnants until they are overwritten. FileVault protects them while the Mac is off." To get a fresh start with a new key afterwards, use Reset (crypto-shredding).

**Temp files:** set `PRAGMA temp_store = MEMORY` so that sorters, transient indices and `IN (SELECT …)` materialisation in `trim()` never spill into `$TMPDIR` ([SQLite temp files](https://www.sqlite.org/tempfiles.html)). Once content is encrypted they would only hold ciphertext and metadata anyway. Keep WAL + `secure_delete=ON` + `checkpoint()` after deletes as they are.

**NSFileProtection:** on Apple silicon, Data Protection defaults to Class C with a volume key, so it already behaves like FileVault. Developers "can also opt in to a higher protection class" ([Apple Platform Security](https://support.apple.com/guide/security/data-protection-overview-secf6276da8a/web)). `FileProtectionType.complete` would make the DB unreadable while the screen is locked. That breaks the hourly `sweep` timer and in-flight writes, gives nothing on Intel Macs, and adds nothing an attacker could not already get from the unlocked session. Not recommended.

**Settings toggle:** do not add an "encrypt" on/off switch. Encryption is always on, so there is a single code path and no reverse migration. Settings → Vitrin gets a status row instead ("Encrypted with a key in your login keychain" / "Locked: Keychain access denied" [Retry]) and **Reset history and key** (wipe rows and files, `SecItemDelete`, new key, `VACUUM`). The existing **Clear history** keeps its meaning.

## Files and symbols that would change

- New `Nubrix/Features/Clipboard/ClipCipher.swift`: `ClipCipher` (master key → HKDF `enc`/`mac`, `seal(_:aad:)`, `open(_:aad:)`, `keyedHash(_:)`, `keyID`).
- New `Nubrix/Features/Clipboard/VitrinKeyStore.swift`: protocol `VitrinKeyProviding` with `KeychainVitrinKeyStore` (file-based SecItem, as in `GitHubTokenStore`) and `#if DEBUG FileVitrinKeyStore`; result enum `.ready/.missing/.locked(OSStatus)`.
- New `Nubrix/Features/Clipboard/ClipSearchIndex.swift`: folded `[UInt8]` buffers, `memmem` AND match, `insert/remove/drop`.
- `ClipDatabase.swift`: `schemaVersion = 3`; `init` adds `temp_store=MEMORY`; `migrate()` adds the new columns and `meta`; `runDeferredMigration()` gains the v3 step; `insert`, `row`, `summary`, `summaries`, `fullText` (decrypt, then prefix in Swift; SQL `substr` no longer applies), `writeImage`/`write` (seal, `.vimg`), new `imageData(named:)`; `thumbnailName(for:)` gets the new extension; `search`/`ftsQuery` are removed after v3 (keep them only for `enc = 0` rows during migration); `ensureFTSSecureDelete` and `backfillBytes` stay for older DBs; new `sweepOrphans()` and `resetAll()`.
- `ClipImageProcessor.swift`: `textHash` and `PreparedClipImage.hash` move to `ClipCipher.keyedHash` (needs the key, so it is computed in `ClipStore.addText`/`addImage` on the store queue). `ClipboardMonitor.capture` stops computing the hash.
- `ClipImageLoader.swift`: `downsample(data:maxPixel:)` (CGImageSource from Data); the URL variants become callers that decrypt first.
- `ClipStore.swift`: `start()` → async key load with ready/locked/reset states and `isReady` semantics; `search()` goes through `ClipSearchIndex`; `copy`, `itemProvider`, `namedDragCopy` (write decrypted bytes rather than `copyItem`), `thumbnail`, `previewImage` decrypt; `shutdown()` drops the index; a screen-lock observer drops the index.
- `ClipItem.swift`: `thumbnailFile` follows the new extension (the rest is unchanged).
- `VitrinSettings.swift`: status row, Retry, Reset history and key.
- `VitrinService.swift`: retry the locked store when the session becomes active.
- Docs: `PRIVACY-AND-SECURITY.md` (Vitrin section: what is encrypted, what is not, the keychain prompt when switching builds), `ROADMAP.md` (Phase 3 "deferred" line, Phase 5 remaining), `TROUBLESHOOTING.md` (Deny → locked, Always Allow).
- No entitlement, `project.pbxproj` or signing script change for the recommended design.

## Tests

A test target is missing. Add `NubrixTests` (Swift Testing) that hosts `ClipDatabase`, `ClipCipher` and `ClipSearchIndex` with an injected `VitrinKeyProviding` mock and a temp directory:
- seal/open round trip; tampered byte, wrong AAD or wrong key → throws, never traps;
- **canary test**: insert the text `"canary-7f3a…"` and an image with a known byte pattern, checkpoint, then scan the raw bytes of `vitrin.sqlite`, `-wal` and every file in the directory: the canary must not appear;
- v2 → v3 migration from a fixture (plaintext rows + PNGs + FTS): all rows `enc = 1`, `clips_fts` gone, PNGs gone, canary absent; simulate a crash by aborting after batch N and re-running, which must give an identical result with no orphans;
- key states: `.missing` with encrypted rows → wiped and fresh; `.locked` → nothing deleted, store not ready; `key_id` mismatch → wiped;
- dedup: the same text twice → one row (HMAC hash); different keys → different hashes;
- search parity: a query set run against the old FTS on the fixture vs the new index (expected differences listed: substring vs prefix); performance guard at 5000 items with a query under 20 ms in Release;
- images: thumbnail and preview decode from `.vimg`, drag copy is a valid PNG, `trim(maxBytes:)` still counts `bytes` correctly.
- Manual QA: a Developer ID release → Apple Development `install-local.sh` → a release again (one prompt per switch, then silence); Deny → locked → Retry; delete the item in Keychain Access → reset banner.

## Recommendation

Use **AES-GCM per field and per file, with the key in the file-based login keychain, and an in-memory `memmem` search index, migrated in place to schema v3**.
- Keychain: SecItem generic password, `kSecUseDataProtectionKeychain = false`, exactly like `GitHubTokenStore`. No entitlement, profile or CI change. Developer ID updates are silent, and one "Always Allow" is needed when switching between local Apple Development and release builds. Debug uses a file key in `Vitrin-Debug/` so it can never wipe or prompt for the real history. Distinguish *locked* (never wipe) from *lost* (wipe, banner).
- Encrypt content, preview, source, images and thumbnails. Replace the SHA-256 dedup with HMAC. Leave sizes, timestamps, kind and pinned in clear.
- Drop FTS5. Search an in-memory folded index built on demand (≈70 ms build, ≤3 ms per query at 5000 items on M4 Max) and dropped on close or lock.
- Migrate in resumable batches with an orphan sweep, then drop FTS, `VACUUM` and checkpoint. Add `temp_store=MEMORY`. Make no promise of physical erasure on SSD/APFS. Skip NSFileProtection.
- Later, optionally move the GitHub token and the Vitrin key to the data protection keychain together, once a Developer ID provisioning profile is part of the release job.
