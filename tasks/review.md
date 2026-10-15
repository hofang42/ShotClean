# ShotClean code review (R6)

Scope: `ShotClean/Package.swift`, `xtool.yml`, `Support/`, `Sources/ShotClean/**`, `Packages/ShotCleanCore/**`
at commit `45cd949`. Read against `SPEC.md`, `UI-SPEC.md`, `tasks/plan.md`. BUG-1..6 (`tasks/bugs.md`) are
not repeated here.

**Verdict: REQUEST CHANGES.** The code is clean and follows the SPEC boundaries closely: the Core uses
Foundation only, there is no networking, deletion only goes through `PHAssetChangeRequest`, and the cache
is protected. I found **no definite compile errors**. Three logic paths can still put a photo into a
delete batch that the user did not choose (REV-1..3).

Counts: **Critical 3 · Important 8 · Suggestion 12**

---

## Compile-risk checklist

The iOS target was never compiled. I checked the code by reading it, and I compiled a probe of the
risky *language* constructs on the local Swift 6.4.1 toolchain in Swift 6 mode. All of them compile.

| Area | Status | Notes |
|---|---|---|
| Package.swift (tools 6.0, `.iOS(.v17)`, one `.library` product, `swiftLanguageModes: [.v6]`, local path dep) | OK | Product/package names resolve (`.product(name: "ShotCleanCore", package: "ShotCleanCore")`). |
| xtool.yml (`version`, `bundleID`, `infoPath`, `iconPath`) | OK | Keys are valid for xtool 1.22. `product` can be omitted because there is only one library. Icon is 1024×1024 RGB with no alpha. |
| Info.plist | OK | Has `NSPhotoLibraryUsageDescription`, `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` and `UILaunchScreen`. No entitlements are needed. |
| iOS 17 availability | OK | The only API newer than iOS 17 is `glassEffect`, and it sits behind `#available(iOS 26, *)` (`GlassOrMaterial.swift:8`). It needs the iOS 26+ SDK, which the Xcode 27 `.xip` in SPEC provides. |
| Missing imports | OK | Charts (ReclaimBar), PhotosUI (limited picker), CryptoKit, `os` (`OSAllocatedUnfairLock`), OSLog, Vision and UIKit are all imported where they are used. ImageIO's `CGImagePropertyOrientation` comes in through Vision/UIKit. |
| `Category` vs `ObjectiveC.Category` ambiguity (Darwin) | App OK / Core tests at risk | The app always uses `ShotCleanCore.Category` or `ShotCategory`. The Core *tests* use bare `Category`, which is ambiguous on Darwin (REV-21). |
| Swift 6 sendability | OK | `PHAsset`, `VN*`, `CGImage` and `FeaturePrintIndex` stay inside one task. Only `UIImage` (Sendable), `String` and `ScreenshotAsset` cross. PhotoKit callbacks capture only Sendable values (continuation, `OSAllocatedUnfairLock`), so they also compile if the SDK marks them `@Sendable`. |
| `@concurrent` (`ScreenshotAnalyzer.swift:34`) | OK | Needs a Swift ≥ 6.2 compiler (xtool uses 6.4.1). Probe compiled. |
| `[weak self]` in an `@Sendable` progress closure from the main actor (`AppModel.swift:151`) | OK | Probe compiled. |
| `if var cache {` on a property, `(cache?.entries.values).map(Array.init) ?? []` (`AppModel.swift:245,254`) | OK | Probe compiled. |
| `ForEach(breakdown, id: \.category)` on labeled tuples, unlabeled → labeled tuple in `compactMap` (`DeleteSummarySheet.swift:70,129`) | OK | Probe compiled. |
| Memberwise inits of views with `@Environment/@State private var` + defaulted `var`s | OK | Probe compiled from another file (CategoryCard, SwipeCard, FloatingActionBar argument orders all match). |
| SwiftUI signatures (`sensoryFeedback(trigger:_:)`, `sensoryFeedback(_:trigger:condition:)`, `ContentUnavailableView`, `MagnifyGesture`, `Button(_:systemImage:action:)`, `presentationDetents`, `ViewThatFits`, `contentTransition(.numericText(value:))`, `@Bindable var router = router`) | OK | All exist on iOS 17 with the parameter labels used here. |
| PhotoKit / Vision signatures (`requestAuthorization(for:) async`, `performChanges(_:) async throws`, `presentLimitedLibraryPicker(from:) async`, `PHPhotosError.userCancelled`, `computeDistance(_:to:)`, `supportedRecognitionLanguages()`, typed `results`) | OK | |
| Type-checker time | Low risk | The longest bodies are `OverviewView.overview`, `SwipeReviewView.body` and `CategoryGridView.body`. They are split into `let`s and helpers. If the first build reports "unable to type-check", split them further. |

Things still to watch on the first real build: SDK-specific `@Sendable`/`@MainActor` annotations on
PhotoKit closures (believed safe, see above), and deprecation warnings on `VN*Request` classes in the
iOS 27 SDK (warnings, not errors).

---

## Critical

### REV-1 — Every scan resets the selection and restores items the user deselected
- **Severity:** Critical (breaks the SPEC rule "only delete what the user selected") · **Confidence:** high
- **Where:** `Sources/ShotClean/App/AppModel.swift:145,162` (`applyAnalysis(..., resetSelection: true)`), `:203-205`; also reached through `presentLimitedLibraryPicker()` (`:95-98`) and `rescan`.
- **Problem:** The overview is shown during an incremental scan by design (`RootView.swift:20`). When the
  scan ends, `selection = analysis.preselectedForDeletion()` replaces the user's choices, and
  `swipeQueue` is rebuilt the same way. Example: the user deselects an expired ticket they want to keep.
  The background scan finishes and the ticket is selected again. "Dọn nhanh N ảnh" then deletes it. The
  iOS dialog only shows a count, so the user cannot catch this. This also makes the `ClusterReviewView`
  keeper override inconsistent (REV-9).
- **Fix:** Reset the selection only on the first result and on a full rescan. After an incremental scan,
  merge: keep the user's choices and add preselection only for ids that were newly analyzed.
  ```swift
  // AppModel
  @ObservationIgnored private var userDeselected: Set<String> = []   // update in a selection API
  private func applyAnalysis(of entries: [AnalyzedScreenshot], newIDs: Set<String>?) async {
    ...
    let pre = analysis.preselectedForDeletion()
    if let newIDs {            // incremental
      selection = selection.filter { featuresByID[$0] != nil }
        .union(pre.intersection(newIDs).subtracting(userDeselected))
    } else {                   // first load / full rescan
      selection = pre; userDeselected = []
    }
  }
  ```
  Call it with `newIDs: Set(output.analyzed.map(\.features.id))` on line 162, and with `nil` when
  `result == nil || full`. Add a unit-style test in the app layer, or at least a manual checklist item.

### REV-2 — Swipe mode can queue a card the user never saw
- **Severity:** Critical (a photo nobody reviewed ends up in the delete batch) · **Confidence:** high
- **Where:** `Views/DesignSystem/SwipeCard.swift:106-119`, `Views/SwipeReviewView.swift:157,161-168,74-103`
- **Problem:** After a swipe, `finish(_:)` animates for 200 ms and then calls `onDecision(action)` from
  an unstructured `Task`. The decision carries no id. `decide(_:)` applies it to
  `items[history.count]`, which means "whatever card is current now". The bottom-bar "Xoá"/"Giữ"
  buttons stay enabled during those 200 ms. If the user swipes right (keep) and taps any button within
  200 ms, the delayed swipe decision lands on the **next** card. That card is queued for deletion (or
  kept) without being shown. The summary sheet shows only counts, so nothing reveals the mistake. The
  `Task` also keeps running after the card is removed.
- **Fix:** Bind each decision to the card id and ignore stale ones:
  ```swift
  // SwipeReviewView.card(for:)
  onDecision: { action in decide(action, for: id) }

  private func decide(_ action: SwipeAction, for id: String? = nil) {
    guard let items, history.count < items.count else { return }
    let current = items[history.count]
    if let id, id != current { return }          // stale callback from a card that already left
    ...append Decision(id: current, action: action)
  }
  ```
  Also disable the bar buttons while a card is leaving. One way: pass `isLeaving` up, or apply the
  decision immediately and animate the card out of the hierarchy with a `.transition`.

### REV-3 — Exact-duplicate SHA-256 hashes the unedited original, so edited copies count as "identical"
- **Severity:** Critical (data loss: an edited screenshot is preselected as "Giống hệt"; SPEC requires 100 % exact-dup precision) · **Confidence:** medium (needs an edited duplicate, e.g. Photos › Duplicate, then crop/markup)
- **Where:** `Analysis/ScreenshotAnalyzer.swift:270-274`
- **Problem:** The code takes `.photo` first, and that resource is the **original** bytes. For an asset
  with adjustments, the visible image is `.fullSizePhoto`. Two assets that share the original but have
  different edits get the same hash. The Core then marks the newer one `exactDuplicate/.delete`, and it
  is preselected. Vision runs on `.current` (line 164), so OCR and hash also disagree about which image
  they describe. `fileSize` also reports the original size.
- **Fix:** Hash the rendered current version when it exists:
  ```swift
  let resource = resources.first(where: { $0.type == .fullSizePhoto })   // current, with edits
    ?? resources.first(where: { $0.type == .photo })
  ```
  Never fall back to `resources.first`, because that could be a non-image resource. Return `nil`
  instead, so the asset is simply left out of exact-dup detection.

---

## Important

### REV-4 — Missing `creationDate` becomes `.distantPast`, so every age rule fires
- **Confidence:** medium (rare for screenshots, but possible for synced or imported assets)
- **Where:** `Analysis/ScreenshotAnalyzer.swift:111`
- **Problem:** `createdAt: asset.creationDate ?? .distantPast` makes the asset look about 2000 years old.
  The QR rule (`age >= 7`), the ticket no-date fallback and the order fallback all suggest **delete**,
  with reasons such as "Mã QR, chụp 739000 ngày trước". Year-less OCR dates are also resolved against
  year 0001.
- **Fix:** Use `asset.creationDate ?? asset.modificationDate ?? Date()`. "Now" is the safe direction
  because it suggests nothing. Alternatively, add `createdAtIsKnown` to the features and skip age-based
  rules when it is false. That needs a Core change; log it in bugs.md.

### REV-5 — Degraded analyses (local thumbnail, no SHA) are cached forever
- **Confidence:** high
- **Where:** `Analysis/ScreenshotAnalyzer.swift:136-143,159`, `App/AnalysisCache.swift:28-33`
- **Problem:** Under R4 the analyzer falls back to `.fastFormat`, which is a small local thumbnail. OCR
  on that is mostly empty, and `sha256` is `nil` when the original is in iCloud. The entry is cached
  and only invalidated by `modificationDate`. When the original is later downloaded, the asset is never
  re-analyzed, so it never gets OCR categories or exact-duplicate detection.
- **Fix:** Store an `isDegraded` flag (or `analysisQuality`) in `AnalyzedScreenshot`. Treat degraded
  entries as `pending` on the next scan. They are cheap to retry because they fail fast without
  network. Also check `info[PHImageResultIsDegradedKey]` in `requestImage` and bump
  `AnalysisCache.formatVersion`.

### REV-6 — Deleting during a background scan brings deleted photos back
- **Confidence:** high
- **Where:** `App/AppModel.swift:124-164` vs `:241-259`
- **Problem:** `scan()` works on a local `cache` copy that was pruned against the assets fetched *before*
  the deletion. When it finishes, `self.cache = cache` (line 160) and `applyAnalysis` (line 162) put the
  deleted ids back into `result`, preselect them again (REV-1), and persist them. The next "Dọn nhanh"
  then calls `deleteAssets`. The fetch finds 0 assets, which returns `0`, and the sheet says "Bạn đã huỷ
  trên hộp thoại của iOS" (REV-17).
- **Fix:** In `delete(_:)`, call `scanTask?.cancel(); await scanTask?.value` first, or keep a
  `deletedIDs` set that `scan()` subtracts before it assigns `self.cache` and `result`. Disabling the
  delete buttons while `phase == .scanning` is the simplest POC fix.

### REV-7 — Nothing is persisted until a scan finishes
- **Confidence:** high
- **Where:** `App/AppModel.swift:150-161`
- **Problem:** The first scan of ≥ 2,000 screenshots takes minutes (R3). If the app is killed, jetsams,
  or is swiped away, all of that work is lost and the scan starts from zero. That goes against the
  intent of US8 ("chỉ phân tích ảnh mới").
- **Fix:** Checkpoint every ~200 analyzed images or every ~30 s. One way: process `pending` in chunks
  and `persist` after each chunk. Another: have `analyze` yield batches through an `AsyncStream`.

### REV-8 — Thumbnails: synchronous `PHAsset` fetch on the main actor per cell, no cancellation, no cache
- **Confidence:** high (performance)
- **Where:** `Library/ScreenshotLibrary.swift:98-125`, `Views/DesignSystem/ThumbnailImage.swift:30-34`
- **Problem:** Every cell does a `PHAsset.fetchAssets(withLocalIdentifiers:)` round trip to the database
  on the main thread, then a `.highQualityFormat` request. When a cell scrolls away, `.task` is
  cancelled but the PhotoKit request is not. Fast scrolling through 1,000+ items queues hundreds of
  decodes. `PHCachingImageManager` is created but `startCachingImages` is never called, and nothing is
  kept in memory, so returning to a grid reloads every image.
- **Fix:**
  - Keep a `[String: PHAsset]` map, or the `PHFetchResult` from `fetchScreenshots`, instead of
    fetching per id.
  - Wrap the request in `withTaskCancellationHandler { … } onCancel: { manager.cancelImageRequest(requestID) }`
    and resume the continuation once (reuse the lock pattern from `ScreenshotAnalyzer.requestImage`).
  - Add an `NSCache<NSString, UIImage>` keyed by `id+size`, and use `.opportunistic` or `.fastFormat`
    for grid cells.

### REV-9 — Cluster keeper override lives in view `@State` while the selection lives in the model
- **Confidence:** medium-high
- **Where:** `Views/ClusterReviewView.swift:19,99-132`
- **Problem:** `setKeeper` changes the persistent `model.selection` (it selects the old keeper and
  deselects the new one). `keeperOverrides` is lost when the user leaves S6. When they come back, the
  Core keeper is drawn with the green "Giữ" tag **and** a selected ring, and the image the user chose
  is shown as a normal member. After REV-1's reset, the reverse happens: the "kept" image is the one
  selected. For exact clusters, one identical copy always survives, so this is not data loss, but the
  UI states the wrong thing about what will be deleted.
- **Fix:** Move `keeperOverrides` into `AppModel`, keyed by cluster keeper id, and clear them when the
  selection is reset. Or derive the displayed keeper from the selection: the single unselected member
  of an exact cluster.

### REV-10 — Cache is one plist with feature prints, rewritten whole on every save
- **Confidence:** medium (performance; measure in R3)
- **Where:** `App/AnalysisCache.swift:73-83`, `App/AppModel.swift:178-184,245-249`
- **Problem:** Each entry holds OCR text plus an `NSKeyedArchiver` feature print. A revision-2 print is
  768 floats, about 3–5 KB archived. With 4,000 screenshots the file is about 15–25 MB. It is fully
  decoded at launch and fully re-encoded and rewritten after **every** scan and **every** delete. That
  costs memory, wears flash, and puts the US8 "< 10 s incremental" target at risk.
- **Fix (MVP):** Store feature prints as raw `Data` in a separate file (or one file per id) that is
  loaded lazily by `FeaturePrintIndex`. Keep the metadata/OCR plist small. Debounce saves.

### REV-11 — Whole library is reclassified twice per launch
- **Confidence:** medium (performance; ties to BUG-6)
- **Where:** `App/AppModel.swift:144-146,162,188-192`
- **Problem:** On launch with cached data, `LibraryAnalyzer.analyze` runs over all entries to show the
  cached result. It runs over all of them again after the incremental scan, even when `pending.isEmpty`.
  With per-image `classify` at a few ms (BUG-6 shows it grows with text size), 4,000 entries ≈ 2 × 4–10 s
  of CPU.
- **Fix:** Skip the second `applyAnalysis` when `pending.isEmpty` and nothing was pruned. Longer term,
  cache folded text, or cache verdicts for rules that do not depend on time.

---

## Suggestion

### REV-12 — Pin the Vision feature-print revision
- **Confidence:** medium · `Analysis/ScreenshotAnalyzer.swift:228`
- `nearDupMaxDistance = 0.35` only makes sense for one revision. If an OS update changes the default,
  new prints cannot be compared with cached ones (`computeDistance` throws, and the code returns `nil`),
  so near-duplicates silently disappear. Set
  `printRequest.revision = VNGenerateImageFeaturePrintRequestRevision2` and store the revision in the
  cache entry so a change invalidates it.

### REV-13 — Missing `CFBundleShortVersionString`/`CFBundleVersion` in Info.plist
- **Confidence:** medium · `Support/Info.plist`, `Views/SettingsView.swift:17-22`
- Settings shows `? (?)` unless xtool injects these keys. Add them explicitly (`1.0`, `1`).

### REV-14 — File protection and load errors
- **Confidence:** medium · `App/AnalysisCache.swift:53-70,78`
- `.completeFileProtection` makes the file unreadable while the device is locked, for example during
  prewarm or if a scan ends right after locking. `load()` then reads "unreadable" as "empty" and starts
  a full rescan. Use `.completeFileProtectionUnlessOpen` (still encrypted at rest). Only start fresh on
  a missing file or a decode error, not on a permission/protection error.

### REV-15 — OCR resolution 1024 px long side
- **Confidence:** medium · `Analysis/ScreenshotAnalyzer.swift:24`
- A 1179×2556 screenshot becomes about 472×1024, so body text is about 8–10 px high. That is below what
  `.accurate` handles well for Vietnamese diacritics, and missed dates affect ticket and order verdicts.
  Measure fixture recall at 1024 vs 1600–2048 during R3 before you lock this in. Memory is bounded by
  `maxConcurrentTasks = 2` either way.

### REV-16 — Per-asset `PHAsset.fetchAssets` and uncancelled PhotoKit requests in the analyzer
- **Confidence:** high (minor performance) · `Analysis/ScreenshotAnalyzer.swift:101,156-182,269-295`
- Each child task runs one database fetch. On cancel, the in-flight `requestImage`/`requestData` keep
  running. Fetch once per batch, for example `fetchAssets(withLocalIdentifiers: batchIDs)` mapped by id,
  and cancel requests through `withTaskCancellationHandler`.

### REV-17 — "0 deleted" is always reported as "user cancelled"
- **Confidence:** high · `Library/ScreenshotLibrary.swift:133-134`, `Views/DeleteSummarySheet.swift:140-149`
- When none of the ids exist any more, `deleteAssets` returns `0` and the UI says the user cancelled
  the iOS dialog. Return a distinct result, for example
  `enum DeleteResult { case deleted(Int), cancelled, nothingToDelete }`.

### REV-18 — Hero "Có thể giải phóng" includes near-duplicates that are never preselected
- **Confidence:** high · `Views/OverviewView.swift:179-190`
- The headline bytes and counts add up all cleanable categories, including `nearDuplicate` (review
  only). "Dọn nhanh" then deletes less than the headline promised. Either leave near-duplicates out of
  the headline or label them "cần xem".

### REV-19 — Near-duplicate keeper is labelled "Nét nhất" but is chosen by pixel area
- **Confidence:** high · `Views/ClusterReviewView.swift:103-106`, Core `DuplicateClusterer.swift:93-97`
- Screenshots from one device all have the same size, so the keeper is effectively the oldest. Say
  "Lớn nhất/Cũ nhất", or compute sharpness. Also note that union-find chains near-duplicates
  transitively: a long scroll capture series taken < 10 min apart becomes one large cluster. That is
  safe (review only) but noisy, so consider capping the cluster time span.

### REV-20 — New screenshots and access changes are not picked up on foreground
- **Confidence:** medium · `Views/RootView.swift:55-60`
- The app re-checks only when `phase == .denied`. A limited → full change made in Settings, or
  screenshots taken while the app was in the background, are not seen until relaunch. On `.active`, run
  `rescan(full: false)` when access changed or when the screenshot count changed. Alternatively, register
  a `PHPhotoLibraryChangeObserver`.

### REV-21 — `Category` name collides with `ObjectiveC.Category` on Darwin
- **Confidence:** high · Core `Tests/ShotCleanCoreTests/EdgeCaseTests.swift:329`, `FixtureTests.swift:76,120`; `Models.swift:166`
- The app works around this with `ShotCleanCore.Category`/`ShotCategory`. The Core tests use bare
  `Category` and will fail with "ambiguous for type lookup" if they are ever run on macOS/Xcode.
  Consider renaming it to `ScreenshotCategory` in the Core, or qualify it in the tests.

### REV-22 — OCR text is selectable and the Debug screen is reachable in release builds
- **Confidence:** high · `Views/ScreenshotDetailView.swift:56-62`, `Views/DebugView.swift:47-49`, `Views/SettingsView.swift:82-84`
- This is fine for the POC, and copying is a user action. For the MVP, wrap Debug and the OCR section
  in `#if DEBUG`, or put them behind a hidden toggle. That way OCR of bank receipts cannot reach the
  pasteboard by accident (SPEC "Never: Lưu text OCR ngoài sandbox").

### REV-23 — SPEC's no-network grep gives a false positive
- **Confidence:** high · `SPEC.md:205` (success criterion 6)
- `grep -rE "URLSession|URLRequest|Network"` matches `isNetworkAccessAllowed` (and comments), so the
  POC check fails even though there is no networking code. Use the stricter pattern from `plan.md:117`:
  `"URLSession|URLRequest|import Network"`. I verified there is no networking code: no `URLSession`,
  `URLRequest`, `import Network` or `print(`.

---

## What's done well
- Core stays Foundation-only. The app layer passes only `String` ids and `ScreenshotAsset` across
  concurrency boundaries, as SPEC requires. `PHAsset`/`VN*` objects never leave the task that made them.
- Continuations are resumed exactly once, guarded by `OSAllocatedUnfairLock` (`ScreenshotAnalyzer.swift:170-180`).
  Vision concurrency is bounded (2) with `autoreleasepool` around each image.
- Deletion follows the safety rules: one `performChanges` batch with the system confirmation, the
  `userCancelled` path is handled, and "Dọn nhanh" uses `selection ∩ preselectedForDeletion()`, so
  manually picked receipts and near-duplicates are never bulk-deleted. Receipts have no "select all" in
  S5 or in "select others" in S6.
- Privacy: no networking; `isNetworkAccessAllowed = false` everywhere; the cache uses file protection
  and is excluded from backup; no logger statement interpolates OCR text or identifiers. Only counts and
  error descriptions are `.public`.
- Accessibility: VoiceOver custom actions replace gestures, there is a Reduce Motion path, and color is
  never the only signal.

## Verification story
- Tests reviewed: Core suite structure and fixtures (passing on Linux per the brief; BUG-1..6 known). There are no app-layer tests. REV-1, REV-2 and REV-6 are good candidates for a small testable `SelectionStore`/`SwipeSession` in the app or the Core.
- Build verified: **no** iOS build (no Darwin SDK). Language-level constructs were probe-compiled on Swift 6.4.1 in Swift 6 mode. Apple API signatures were checked by reading.
- Security checked: yes. No networking, file protection, backup exclusion, logging privacy and no private API, with the notes in REV-14 and REV-22.
