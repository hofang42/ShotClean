# ShotClean fix verification (R8)

Scope: `git diff bb603cb HEAD` (commits `d34023b` core, `d2ea792` app). Checked by reading the code, because there is no
iOS SDK here. Core suite: **92 tests in 9 suites pass** on Linux (WSL, Swift 6.4.1) at HEAD.

**Result:** 29 items checked (REV-1..23 and BUG-1..6). **Verified 25 · Partly fixed 2 (REV-8, REV-16) · Deferred by decision 2 (REV-10, REV-15) · Not fixed 0 · Regressed 0.**
I found no Critical issue left. There are 3 new findings: 1 Important and 2 Suggestions, plus notes in the table.

## Review items (REV)

| ID | Sev | Status | Evidence |
|---|---|---|---|
| REV-1 selection reset on scan | Crit | **Verified** | `App/SelectionState.swift:28-41`. `merge` keeps the user's choice for every id the user touched (a deselected id stays deselected). Preselection is added only for ids that are new since the last merge (`:33`). Ids that vanished are dropped. `AppModel.swift:215` resets only on a full rescan or the first result. Views no longer write `selection` (it is a get-only computed property, `AppModel.swift:34`); every call site goes through `toggleSelection` / `setSelected` / `setKeeper`. |
| REV-2 swipe decision lands on next card | Crit | **Verified** | `SwipeCard.swift:62-70`: the decision is delivered by `.task(id: leavingAction)`, so it is cancelled with the card. `SwipeReviewView.swift:160,166-175`: the callback is bound to the card id, so a stale id is ignored. All bar buttons, Undo and "Xong" are disabled while `leavingID != nil`. VoiceOver actions are blocked while the card is leaving (`decideNow`). The top card has a stable `.id(queue[position])`, so the task is not cancelled in the middle of the animation. If the view disappears, `.task` re-runs on reappear and still delivers the decision, so `leavingID` cannot get stuck. |
| REV-3 edited copy hashed as original | Crit | **Verified** | `ScreenshotAnalyzer.swift:289`: the code hashes `.fullSizePhoto` when `hasAdjustments` is true and `.photo` otherwise. There is no `resources.first` fallback; the result is `nil` instead. `PHAsset.hasAdjustments` is iOS 15+, so it is OK on iOS 17. Mixed pairs (edited vs unedited) can never match, which is the safe direction. |
| REV-4 missing creationDate → age rules | Imp | **Verified** | App: `ScreenshotAnalyzer.swift:114` maps a missing date to `CaptureDate.unknown`. `AppModel.swift:288` removes undated ids from the preselection. Views use `captureDate(for:)`. Core: `ScreenshotClassifier.swift:29` uses `capturedAt = nil` before 2000-01-01, so the QR and fallback rules are skipped (test `unknownCaptureDate`). The sentinel value is duplicated in `CaptureDate.swift:14`; it matches the Core value (946 684 800). |
| REV-5 degraded analyses cached forever | Imp | **Verified** (see NEW-1) | `AnalysisCache.swift:52`, `ScreenshotAnalyzer.swift:127` (`PHImageResultIsDegradedKey` is checked). `formatVersion` is now 2, and a version probe runs before the full decode. |
| REV-6 delete during scan resurrects photos | Imp | **Verified** (see NEW-2) | `deletedIDs` is filtered at fetch, per chunk, at the checkpoint and at the end (`AppModel.swift:162-206`). A generation counter guards `applyAnalysis`. Deleted ids no longer come back, and selection, swipe queue and cache are reconciled. |
| REV-7 no checkpoint | Imp | **Verified** | Chunks of 100 are analyzed, with a 30 s throttled `persist` (`AppModel.swift:186-203`). |
| REV-8 thumbnails | Imp | **Partly fixed** | Done: `NSCache` (64 MB), request cancellation through `PhotoRequest`, and a per-id `PHAsset` map. Still open: the first display of each cell does a synchronous `PHAsset.fetchAssets` on the main actor (`ScreenshotLibrary.swift:142-148`), and `library.forget()` clears the map and the image cache at the start of every scan (`AppModel.swift:161`). This is a Suggestion. |
| REV-9 keeper override in view state | Imp | **Verified** | Overrides live in `SelectionState.keeperOverrides`. They are cleared on reset and pruned on merge/remove. `ClusterReviewView` reads `model.keeper(of:)`. |
| REV-10 single big plist | Imp | **Deferred** (won't fix now) | This is acceptable for the POC. Saves are now skipped when nothing changed. It has to be measured in R3. |
| REV-11 double classification | Imp | **Verified** | The skip condition is at `AppModel.swift:213-216`. Its benefit is largely lost when degraded entries exist (NEW-1). |
| REV-12 feature-print revision | Sug | **Verified** | `ScreenshotAnalyzer.swift:242`; the revision-2 constant exists on iOS 17. The cache version was bumped. |
| REV-13 version keys | Sug | **Verified** | `Support/Info.plist`. |
| REV-14 file protection / load errors | Sug | **Verified** | `AnalysisCache.swift:114` uses `.completeFileProtectionUnlessOpen`. `.unavailable` means the file is never overwritten (`AppModel.swift:236`, `persist` guard). Note: after `.unavailable` the load is never retried in that session, so that launch re-analyzes everything in memory. This is a Suggestion. |
| REV-15 OCR resolution | Sug | **Deferred** | Will be measured in R3. |
| REV-16 analyzer requests uncancelled | Sug | **Partly fixed** | Image and data requests are now cancelled through `PhotoRequest`. The per-asset fetch stays as it is; the stated reason (PHAsset is not Sendable) is sound. |
| REV-17 0 deleted = cancelled | Sug | **Verified** | `DeleteResult.swift`, `ScreenshotLibrary.swift:174-191`, and a separate `nothingToDelete` message in the sheet. |
| REV-18 hero includes near-dups | Sug | **Verified** | `OverviewView.swift:187-195`. |
| REV-19 "Nét nhất" label | Sug | **Verified** | Now `keeperLargest` = "Lớn nhất". The cluster-span cap is still a product decision. |
| REV-20 foreground refresh | Sug | **Verified** | `AppModel.swift:107-125`, `RootView.swift:55-60`. Note: the iOS delete-confirmation alert also flips the scene from inactive to active, so an incremental rescan can start right after a delete. `deletedIDs` and the generation counter make this harmless, but the UI shows a short "scanning" phase. |
| REV-21 `Category` ambiguity | Sug | **Verified** | The tests use `ShotCleanCore.Category`. |
| REV-22 OCR text / Debug in release | Sug | **Verified** | `#if DEBUG` is used at `ScreenshotDetailView.swift:60` and `SettingsView.swift:83`. `#if` inside a ViewBuilder is valid. |
| REV-23 SPEC grep | Sug | **Verified** | SPEC.md criterion 6 now uses `import Network`. The grep over `Sources` returns nothing. (review.md says "left for SPEC owner", but the SPEC diff shows it was changed.) |

## Core bugs (BUG)

| ID | Status | Evidence |
|---|---|---|
| BUG-1 ShopeePay order → receipt | **Verified** | `withKnownIssue` and the manifest `knownIssue` were removed, and the fixture now asserts `expiredOrder/delete`. The rule is at `ScreenshotClassifier.swift` `isTransferReceipt`. |
| BUG-2 "cake" chat → receipt | **Verified** | The fixture asserts `other`. New tests: `ambiguousBankWord`, `ambiguousBankWithStrongField`. |
| BUG-3 news → expired order | **Verified** | The fixture and `brandAloneIsNotOrder` test pass. |
| BUG-4 maps transit → ticket | **Verified** | The fixture and `genericTravelWords` test pass. |
| BUG-5 year roll-forward | **Verified** | `yearBoundaryForward` and `yearBoundaryUpcomingTicket` now assert without a wrapper. |
| BUG-6 50 KB perf | **Verified** (see NEW-3) | The 50 ms threshold is unchanged and the test passes. |

**Test-weakening check (diff of `Tests/`):** no threshold was raised. `precision >= 0.95` is unchanged, and `total > 0` was added. No
expected label in the manifest changed; only the `knownIssue` fields were removed. Every `withKnownIssue` was replaced by a plain
`#expect`, which makes the tests stricter. The remaining test changes are swift-format re-wrapping and new tests. The one change in
measurement method is in NEW-3.

## SPEC safety boundaries

| Rule | Holds? | Evidence |
|---|---|---|
| Never auto-delete | Yes | `model.delete` is called only from `DeleteSummarySheet.swift:141` after a user tap, and every path goes through `router.requestDeletion`. |
| Deletion only via `PHAssetChangeRequest` + system confirm | Yes | `ScreenshotLibrary.swift:184`, one `performChanges` batch. |
| Receipts / near-dups never preselected | Yes | The Core `preselectedForDeletion` is untouched. `merge` adds only ids from that set (`SelectionState.swift:32-33`). Quick clean is `selection ∩ preselected` (`OverviewView.swift:62`). `setKeeper` never selects a receipt, and never selects anything in a near cluster. |
| No networking | Yes | `grep -rE "URLSession\|URLRequest\|import Network\|print\("` over `Sources` returns nothing. `isNetworkAccessAllowed = false` is kept in every request. |
| Logging privacy | Yes | New log lines interpolate only counts, a Bool and error descriptions. No OCR text or ids are logged. |
| Cache protection / no backup | Yes | The cache is encrypted at rest (`completeUnlessOpen`), `isExcludedFromBackup` is still set, and the file is never overwritten when unreadable. |

## Compile-risk review of the new code (by reading)

- `PhotoRequest` (`Library/PhotoRequest.swift`): `OSAllocatedUnfairLock<State>` holds Sendable state (`CheckedContinuation`, `@Sendable` closure). The `withLock` bodies return Sendable values. Using the non-escaping `start` inside the non-escaping operation and continuation closures is legal. `isolation: isolated (any Actor)? = #isolation` lets the MainActor caller pass a non-Sendable `PHAsset` into `start`. The PhotoKit handlers are formed in nonisolated code (`startThumbnailRequest`, static analyzer funcs), so there is no MainActor-assert crash. Resume-once logic is correct, including a synchronous callback and a cancel before install. **Low risk.**
- `SelectionState.setSelected(_:for: String)` vs `(_:for: some Sequence<String>)`: there is no ambiguity, because `String` is a `Sequence<Character>`.
- `switch try await model.delete(...)`, `Duration` comparison, `.task(id:)` with `SwipeAction: Equatable`, `VNGenerateImageFeaturePrintRequestRevision2`, `PHAsset.hasAdjustments`, `.completeFileProtectionUnlessOpen`, `PHImageResultIsDegradedKey`, `cancelDataRequest` / `cancelImageRequest`: all exist with these signatures on iOS 17.
- `SwipeCard` `.task` closure calls `onDecision` (non-Sendable stored closure). With the iOS 26+ SDK, `task` takes a `sending`/`@isolated(any)` closure that inherits MainActor, so this is fine. It is the same pattern the original `Task {}` used. **Low risk.**

## New findings

### NEW-1 — Important — Assets whose original is only in iCloud are re-analyzed on every scan
- **Where:** `ScreenshotAnalyzer.swift:127` (`isDegraded: image.isDegraded || digest == nil`), `AnalysisCache.swift:52-55`, `AppModel.swift:168`.
- **Problem:** With "Optimize iPhone Storage", many originals are never local. Network is off, so `digest == nil` every time, the entry stays degraded forever, and it lands in `pending` on every scan, including the foreground refresh. That means a Vision OCR pass and two PhotoKit requests per such asset on every launch. This breaks the US8 target ("< 10 s incremental with ≤ 50 new"), and it disables the REV-11 skip because `pending` is never empty. The fix for REV-5 traded "never retried" for "always retried".
- **Fix:** Retry degraded entries only when something could have changed. For example, store `degradedAt` and the reason (thumbnail vs no hash), and re-queue only when `modificationDate` changed, or once per N days, or when a cheap check (`PHAssetResource` locally available via `requestData` probe, or `PHImageManager` high-quality request success) succeeds. At minimum, do not re-OCR when the image was full-quality and only the hash was missing; only retry the hash.

### NEW-2 — Suggestion — Delete during a launch's first scan leaves a stale overview until the scan ends
- **Where:** `AppModel.swift:228` (`startingCache` returns the loaded cache without assigning `self.cache`), `AppModel.swift:366` (`guard var cache else { return outcome }`).
- **Problem:** On every launch with a cache, the cached result is shown while the scan runs, but `self.cache` is `nil` until the scan finishes. A delete in that window updates the selection and swipe queue, but `result`, `featuresByID` and the hero bytes still contain the deleted ids until the scan ends. A deleted thumbnail shows blank. If the user re-selects it, the result is "nothingToDelete". This is not a safety issue.
- **Fix:** Assign `self.cache = loaded` in `startingCache`, or, when `cache == nil`, reclassify from `featuresByID` minus `ids`.

### NEW-3 — Suggestion — Perf test now uses best-of-5 timing
- **Where:** `EdgeCaseTests.swift:48-51`.
- **Problem:** The 50 ms threshold is unchanged, but the test now takes the minimum of 5 runs instead of one sample. That is a slightly softer measurement. The change is justified (it removes flakiness), and the isolated time (≈ 7 ms) is far below budget, so I do not count it as weakening the test. A median would be a stricter way to deflake it.

### Other notes (Suggestion, no action required for POC)
- Receipt rule tightening (BUG-1/2): a real receipt with no success phrase, no strong field and only one generic field is now `other`. It can then fall through to the QR rule (old receipt + QR leads to delete). The fixtures still show 0 receipts deleted. Re-check with real receipts in R3.
- `SelectionState.merge`: ids that leave and later return (limited access shrink, then grow) count as "new" and are preselected again, and the user's earlier deselection is forgotten. Ids that become preselected only as they age (e.g. a ticket that expires) are not auto-selected until a full rescan. Both are in the safe or rare direction.

## Resolution — R7b app-fixer (2026-10-15) — NOT COMPILED (no iOS SDK)
- **NEW-1 — Resolution: fixed.** `AnalyzedScreenshot.isDegraded: Bool` → `degradedAt: Date?` (`isDegraded` is now computed). `AnalysisCache.needsAnalysis(_:now:)` re-queues a cached entry only when `modificationDate` changed (stale), on a full rescan (empty cache), or when it is degraded and `degradedRetryInterval` (24 h) has passed since the last attempt. A failed retry stamps a new `degradedAt`. iCloud-only screenshots are therefore re-OCR'd at most once a day, so `pending` can be empty again and the REV-11 skip works. `formatVersion` → 3.
- **NEW-2 — Resolution: fixed.** `AppModel.startingCache` assigns the loaded cache to `self.cache`, so a delete during a launch's first scan reclassifies right away and removes the deleted ids from `result`, `featuresByID` and the hero. The scan keeps its own copy and still subtracts `deletedIDs` before publishing.
