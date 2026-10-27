import Foundation
import Observation
import ShotCleanCore
import UIKit

/// Single source of truth for the UI (contract: tasks/plan.md, "App layer").
///
/// Launch flow for views:
/// - Root view: `.task { if model.hasCompletedOnboarding { await model.start() } }`
/// - Onboarding button (S1): `await model.start()` (marks onboarding done).
/// - Permission priming (S2): `await model.requestPermission()`.
/// - Scene becomes active: `await model.refreshAfterForeground()` (E1, REV-20).
@MainActor
@Observable
final class AppModel {
  enum Phase: Equatable {
    case needsOnboarding
    case needsPermission
    case denied
    case scanning(done: Int, total: Int)
    case ready
  }

  private(set) var phase: Phase
  private(set) var isLimitedAccess = false
  /// Latest analysis. During an incremental scan this holds the cached result, so the overview
  /// can be shown while `phase == .scanning`.
  private(set) var result: AnalysisResult?
  /// id → file size in bytes, only for screenshots whose rendition was hashed on device.
  private(set) var sizes: [String: Int64] = [:]
  /// Selection bookkeeping; rescans merge into it instead of replacing it (REV-1).
  private(set) var selectionState = SelectionState()
  /// Ids currently selected for deletion. Change it through the selection methods below.
  var selection: Set<String> { selectionState.selected }
  /// Ids to review in swipe mode (S7): `.delete` then `.review` suggestions, by category priority.
  private(set) var swipeQueue: [String] = []

  // Additions beyond the plan contract (read-only, for S4 / Debug).
  /// Total number of screenshots visible to the app (the "/ 3.800" in S4).
  private(set) var screenshotCount = 0
  /// Screenshots that could not be analyzed without network access (risk R4).
  private(set) var unavailableIDs: Set<String> = []
  private(set) var hasCompletedOnboarding: Bool
  /// User-tunable rules (S9). Change through `updateSettings(_:)`.
  private(set) var settings: CleanupSettings
  /// Automatic preselection under the current settings (S4 quick clean). Never receipts.
  private(set) var preselectedIDs: Set<String> = []

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let library = ScreenshotLibrary()
  @ObservationIgnored private let analyzer = ScreenshotAnalyzer(maxConcurrentTasks: 2)
  @ObservationIgnored private var cache: AnalysisCache?
  /// `false` when the cache file exists but could not be read; it must not be overwritten.
  @ObservationIgnored private var canPersistCache = true
  @ObservationIgnored private var featuresByID: [String: ScreenshotFeatures] = [:]
  /// Ids without a known capture date; never preselected (REV-4).
  @ObservationIgnored private var undatedIDs: Set<String> = []
  @ObservationIgnored private var scanTask: Task<Void, Never>?
  /// Ids deleted this session. A scan that started before a deletion never brings them back (REV-6).
  @ObservationIgnored private var deletedIDs: Set<String> = []
  /// Bumped by every `applyAnalysis`; an older, slower classification never overwrites a newer one.
  @ObservationIgnored private var analysisGeneration = 0
  /// Latest cache snapshot waiting for the debounced save, the debounce timer, and the last
  /// write (writes are chained, so they land in order).
  @ObservationIgnored private var pendingSave: AnalysisCache?
  @ObservationIgnored private var saveDebounce: Task<Void, Never>?
  @ObservationIgnored private var lastSave: Task<Void, Never>?

  private static let onboardingKey = "hasCompletedOnboarding"
  /// Assets analyzed per chunk; the cache is checkpointed between chunks (REV-7).
  private static let chunkSize = 100
  private static let checkpointInterval: Duration = .seconds(30)
  private static let saveDelay: Duration = .seconds(2)

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    settings = CleanupSettings.load(from: defaults)
    let onboarded = defaults.bool(forKey: Self.onboardingKey)
    hasCompletedOnboarding = onboarded
    if !onboarded {
      phase = .needsOnboarding
    } else {
      switch ScreenshotLibrary.currentAccess() {
      case .notDetermined: phase = .needsPermission
      case .denied: phase = .denied
      case .authorized, .limited: phase = .scanning(done: 0, total: 0)
      }
    }
  }

  // MARK: Flow

  /// Onboarding done → permission state → scan (incremental) when access is granted.
  func start() async {
    if !hasCompletedOnboarding {
      hasCompletedOnboarding = true
      defaults.set(true, forKey: Self.onboardingKey)
    }
    await apply(ScreenshotLibrary.currentAccess())
  }

  /// Shows the system permission prompt (`.readWrite`), then scans if granted.
  func requestPermission() async {
    let access = await ScreenshotLibrary.requestAccess()
    Log.app.info("Photo access after request: \(String(describing: access), privacy: .public)")
    await apply(access)
  }

  private func apply(_ access: PhotoAccess) async {
    isLimitedAccess = access == .limited
    switch access {
    case .notDetermined: phase = .needsPermission
    case .denied: phase = .denied
    case .authorized, .limited: await rescan(full: false)
    }
  }

  /// Scene became active (E1, REV-20): picks up access changes made in Settings and screenshots
  /// taken while the app was in the background.
  func refreshAfterForeground() async {
    guard hasCompletedOnboarding else { return }
    let access = ScreenshotLibrary.currentAccess()
    switch phase {
    case .needsOnboarding, .needsPermission, .scanning:
      return
    case .denied:
      await apply(access)
    case .ready:
      guard access.canRead, (access == .limited) == isLimitedAccess else {
        await apply(access)
        return
      }
      let count = await Task.detached(priority: .utility) {
        ScreenshotLibrary.screenshotCount()
      }.value
      if count != screenshotCount { await rescan(full: false) }
    }
  }

  /// Extends a limited selection with the system picker, then rescans incrementally.
  func presentLimitedLibraryPicker() async {
    await library.presentLimitedLibraryPicker()
    await rescan(full: false)
  }

  // MARK: Scanning

  /// Scans screenshots. `full == false` analyzes only assets missing from the cache (or
  /// analyzed in degraded quality); `full == true` discards the cache first and resets the
  /// selection. Waits for any running scan to stop.
  func rescan(full: Bool) async {
    guard ScreenshotLibrary.currentAccess().canRead else {
      await apply(ScreenshotLibrary.currentAccess())
      return
    }
    if let running = scanTask {
      running.cancel()
      await running.value
    }
    let task = Task { await self.scan(full: full) }
    scanTask = task
    await task.value
    if scanTask == task { scanTask = nil }
  }

  /// Stops the current scan. Finished analyses are kept and cached.
  func cancelScan() {
    scanTask?.cancel()
  }

  private func scan(full: Bool) async {
    var cache = await startingCache(full: full)

    let fetched = await Task.detached(priority: .userInitiated) {
      ScreenshotLibrary.fetchScreenshots()
    }.value
    let assets = fetched.filter { !deletedIDs.contains($0.id) }
    screenshotCount = assets.count
    // REV-8: keep thumbnails across scans; drop only ids that vanished or were modified.
    let modified = Set(
      assets.filter { cache.entries[$0.id] != nil && cache.validEntry(for: $0) == nil }
        .map(\.id))
    let pruned = cache.prune(keeping: Set(assets.map(\.id)))
    library.forget(pruned.union(modified))
    if !pruned.isEmpty {
      await Task.detached(priority: .utility) { FeaturePrintStore.remove(pruned) }.value
    }
    let scanStart = Date()
    let pending = assets.filter { cache.needsAnalysis($0, now: scanStart) }
    Log.app.info(
      "Scan: \(assets.count) screenshots, \(pending.count) to analyze, full=\(full, privacy: .public)"
    )

    // Show cached results right away; the scan continues behind them.
    let hadResult = result != nil
    if !full, !hadResult, !cache.entries.isEmpty {
      await applyAnalysis(of: entries(of: cache, in: assets), reset: true)
    }

    let total = pending.count
    phase = .scanning(done: 0, total: total)
    var unavailable: Set<String> = []
    var done = 0
    let clock = ContinuousClock()
    var lastCheckpoint = clock.now
    for start in stride(from: 0, to: pending.count, by: Self.chunkSize) {
      if Task.isCancelled { break }
      let chunk = Array(pending[start..<min(start + Self.chunkSize, pending.count)])
      let offset = done
      let output = await analyzer.analyze(chunk) { [weak self] processed in
        await self?.reportProgress(done: offset + processed, total: total)
      }
      // REV-10: prints go to their own small files, written once; the plist never holds them.
      let prints = output.featurePrints
      await Task.detached(priority: .utility) { FeaturePrintStore.write(prints) }.value
      for entry in output.analyzed where !deletedIDs.contains(entry.features.id) {
        cache.entries[entry.features.id] = entry
      }
      unavailable.formUnion(output.unavailableIDs)
      done += chunk.count
      // REV-7: checkpoint, so a killed app does not lose minutes of work.
      if clock.now - lastCheckpoint >= Self.checkpointInterval {
        cache.remove(deletedIDs)
        scheduleSave(cache)
        lastCheckpoint = clock.now
      }
    }

    // REV-6: deletions made while this scan ran must not come back.
    cache.remove(deletedIDs)
    let liveAssets = assets.filter { !deletedIDs.contains($0.id) }
    unavailableIDs = unavailable.subtracting(deletedIDs)
    screenshotCount = liveAssets.count
    self.cache = cache

    // REV-11: nothing new and the cached result is already shown → skip reclassifying.
    if full || !pending.isEmpty || !pruned.isEmpty || !hadResult {
      scheduleSave(cache)
      await applyAnalysis(of: entries(of: cache, in: liveAssets), reset: full || result == nil)
    }
    phase = .ready
  }

  /// The cache a scan starts from: empty for a full rescan, else the in-memory or stored one.
  private func startingCache(full: Bool) async -> AnalysisCache {
    if full {
      if canPersistCache {
        await Task.detached(priority: .utility) { AnalysisCache.deleteFile() }.value
      }
      return AnalysisCache()
    }
    if let cache { return cache }
    let loaded = await Task.detached(priority: .userInitiated) { AnalysisCache.load() }.value
    switch loaded {
    case .loaded(let cache):
      canPersistCache = true
      // NEW-2: a deletion during this first scan can reclassify from it right away; the scan
      // still works on its own copy and drops `deletedIDs` before publishing.
      self.cache = cache
      return cache
    case .unavailable:
      // REV-14: never overwrite an unreadable (e.g. locked) file; work in memory this session.
      canPersistCache = false
      return AnalysisCache()
    }
  }

  private func reportProgress(done: Int, total: Int) {
    guard case .scanning = phase else { return }
    phase = .scanning(done: done, total: total)
  }

  /// Cached entries for `assets`, in asset order (oldest first).
  private func entries(of cache: AnalysisCache, in assets: [ScreenshotAsset])
    -> [AnalyzedScreenshot]
  {
    assets.compactMap { cache.validEntry(for: $0) }
  }

  /// Debounced save (REV-10): a burst of changes (checkpoint, scan end, several deletions)
  /// produces one write of the small metadata/OCR plist.
  private func scheduleSave(_ cache: AnalysisCache) {
    guard canPersistCache else { return }
    pendingSave = cache
    saveDebounce?.cancel()
    saveDebounce = Task { [weak self] in
      do {
        try await Task.sleep(for: AppModel.saveDelay)
      } catch {
        return
      }
      await self?.flushSave()
    }
  }

  /// Writes the pending snapshot now; call when the scene goes to the background. Writes are
  /// chained, so an older snapshot can never land after a newer one.
  func flushSave() async {
    saveDebounce?.cancel()
    saveDebounce = nil
    guard canPersistCache, let snapshot = pendingSave else { return }
    pendingSave = nil
    let previous = lastSave
    let task = Task.detached(priority: .utility) {
      await previous?.value
      do {
        try snapshot.save()
      } catch {
        Log.cache.error("Failed to save cache: \(error.localizedDescription, privacy: .public)")
      }
    }
    lastSave = task
    await task.value
  }

  // MARK: Analysis

  /// Classifies `entries` off the main actor and publishes the result. `reset` starts the
  /// selection over (first result, full rescan); otherwise the user's choices are merged in.
  private func applyAnalysis(
    of entries: [AnalyzedScreenshot], reset: Bool, reapply: Bool = false
  ) async {
    analysisGeneration += 1
    let generation = analysisGeneration
    let now = Date()
    let thresholds = settings.thresholds
    let analysis = await Task.detached(priority: .userInitiated) {
      AppModel.classify(entries, now: now, thresholds: thresholds)
    }.value
    // A newer analysis (e.g. after a deletion) started meanwhile; it wins.
    guard generation == analysisGeneration else { return }

    featuresByID = Dictionary(
      entries.map { ($0.features.id, $0.features) }, uniquingKeysWith: { first, _ in first })
    var sizes: [String: Int64] = [:]
    var undated: Set<String> = []
    for entry in entries {
      if let size = entry.features.fileSize { sizes[entry.features.id] = size }
      if !CaptureDate.isKnown(entry.features.createdAt) { undated.insert(entry.features.id) }
    }
    self.sizes = sizes
    result = analysis

    undatedIDs = undated
    let preselected = preselection(for: analysis)
    preselectedIDs = preselected
    let known = Set(featuresByID.keys)
    if reapply {
      selectionState.reapply(knownIDs: known, preselected: preselected)
    } else if reset {
      selectionState.reset(knownIDs: known, preselected: preselected)
    } else {
      selectionState.merge(knownIDs: known, preselected: preselected)
    }
    swipeQueue = Self.swipeOrder(for: analysis, enabled: settings.enabledCategories)
    // REV-8: one batched, off-main PHAsset fetch for the ids the cells will ask for.
    await library.syncAssets(with: known)
  }

  /// Runs `LibraryAnalyzer` with a feature-print distance. Off the main actor.
  nonisolated private static func classify(
    _ entries: [AnalyzedScreenshot], now: Date, thresholds: Thresholds
  ) -> AnalysisResult {
    // REV-10: prints are read lazily, only for the pairs the clusterer compares.
    let index = FeaturePrintIndex(load: FeaturePrintStore.read)
    return LibraryAnalyzer(thresholds: thresholds).analyze(
      entries.map(\.features),
      distance: { index.distance($0, $1) },
      now: now
    )
  }

  private static func swipeOrder(
    for analysis: AnalysisResult, enabled: Set<ShotCleanCore.Category>
  ) -> [String] {
    let suggested: (Verdict.Suggestion) -> [String] = { suggestion in
      ShotCleanCore.Category.allCases.filter(enabled.contains).flatMap { category in
        analysis.ids(in: category).filter { analysis.verdicts[$0]?.suggestion == suggestion }
      }
    }
    return suggested(.delete) + suggested(.review)
  }

  // MARK: Selection (explicit user choices; a rescan never overrides them)

  func toggleSelection(_ id: String) {
    selectionState.toggle(id)
  }

  func setSelected(_ isSelected: Bool, for ids: some Sequence<String>) {
    selectionState.setSelected(isSelected, for: ids)
  }

  /// Keeper shown for `cluster`: the user's choice if any, else the settings rule (REV-9).
  func keeper(of cluster: Cluster) -> String {
    selectionState.keeper(
      forCoreKeeper: cluster.keeperID, members: cluster.memberIDs,
      defaultKeeper: defaultKeeper(of: cluster))
  }

  /// Keeper picked by `settings.keeperRule`. Receipts win so they are never the ones deleted.
  private func defaultKeeper(of cluster: Cluster) -> String {
    let members = cluster.memberIDs
    if let receipt = members.first(where: {
      result?.verdicts[$0]?.category == .transferReceipt
    }) {
      return receipt
    }
    let date: (String) -> Date = { self.featuresByID[$0]?.createdAt ?? .distantPast }
    switch settings.keeperRule {
    case .automatic: return cluster.keeperID
    case .oldest: return members.min { date($0) < date($1) } ?? cluster.keeperID
    case .newest: return members.max { date($0) < date($1) } ?? cluster.keeperID
    case .largestFile:
      return members.max { (sizes[$0] ?? 0) < (sizes[$1] ?? 0) } ?? cluster.keeperID
    }
  }

  /// Ids preselected for deletion under the current settings.
  /// - REV-4: a screenshot without a capture date is never preselected.
  /// - Only enabled categories; receipts never.
  /// - Duplicate clusters follow the keeper rule: everyone but the default keeper.
  /// - A member matched by another rule (receipt, expired ticket…) keeps that rule's say.
  /// - Order independent: a keeper of any enabled cluster is never picked by the cluster pass,
  ///   even when it is a non-keeper of an overlapping cluster (exact keeper inside a near one).
  private func preselection(for analysis: AnalysisResult) -> Set<String> {
    let enabled = settings.enabledCategories
    // Exact-duplicate verdicts are decided below with the keeper rule, not by the Core keeper.
    let byRule = analysis.preselectedForDeletion().filter { id in
      guard let category = analysis.verdicts[id]?.category, category != .exactDuplicate else {
        return false
      }
      return enabled.contains(category)
    }
    var byCluster: Set<String> = []
    var keepers: Set<String> = []
    for cluster in analysis.clusters {
      let kindEnabled =
        cluster.kind == .exact
        ? enabled.contains(.exactDuplicate)
        : enabled.contains(.nearDuplicate) && settings.preselectNearDuplicates
      guard kindEnabled else { continue }
      let keeper = defaultKeeper(of: cluster)
      keepers.insert(keeper)
      for id in cluster.memberIDs where id != keeper {
        let category = analysis.verdicts[id]?.category
        if category == .exactDuplicate || category == .nearDuplicate || category == .other {
          byCluster.insert(id)
        }
      }
    }
    return byRule.union(byCluster.subtracting(keepers)).subtracting(undatedIDs)
  }

  /// Applies new rules: saves them and reclassifies the cached analyses (no rescan).
  func updateSettings(_ newSettings: CleanupSettings) async {
    guard newSettings != settings else { return }
    settings = newSettings
    newSettings.save(to: defaults)
    // No cache yet (first scan running): that scan classifies with the new settings.
    guard let cache else { return }
    let ordered = cache.entries.values.sorted {
      ($0.features.createdAt, $0.features.id) < ($1.features.createdAt, $1.features.id)
    }
    // Nothing published yet: there are no user choices to keep, start from the preselection.
    let hasResult = result != nil
    await applyAnalysis(of: ordered, reset: !hasResult, reapply: hasResult)
  }

  /// The user picks a new keeper: it is deselected. For exact duplicates the previous keeper is
  /// selected instead, unless it is a receipt. Near duplicates are never auto-selected.
  func setKeeper(_ newKeeper: String, in cluster: Cluster) {
    let oldKeeper = keeper(of: cluster)
    let oldIsReceipt = result?.verdicts[oldKeeper]?.category == .transferReceipt
    selectionState.setKeeper(
      newKeeper, coreKeeperID: cluster.keeperID, members: cluster.memberIDs,
      defaultKeeper: defaultKeeper(of: cluster),
      selectPreviousKeeper: cluster.kind == .exact && !oldIsReceipt)
  }

  // MARK: Actions

  /// Deletes `ids` after the iOS confirmation dialog (one `PHAssetChangeRequest` batch, one
  /// dialog). Deleted photos go to "Recently Deleted".
  func delete(_ ids: Set<String>) async throws -> DeleteResult {
    let outcome = try await ScreenshotLibrary.deleteAssets(withIDs: Array(ids))
    if outcome == .cancelled { return outcome }

    // `.deleted` or `.nothingToDelete`: none of `ids` exist any more.
    let removedCount = ids.intersection(featuresByID.keys).count
    deletedIDs.formUnion(ids)
    library.forget(ids)
    await Task.detached(priority: .utility) { FeaturePrintStore.remove(ids) }.value
    screenshotCount = max(0, screenshotCount - removedCount)
    unavailableIDs.subtract(ids)
    selectionState.remove(ids)
    swipeQueue.removeAll { ids.contains($0) }
    // No in-memory cache yet (first-ever scan, or unreadable file): the running scan drops
    // `deletedIDs` and publishes the reconciled result when it ends.
    guard var cache else { return outcome }
    cache.remove(ids)
    self.cache = cache
    scheduleSave(cache)
    let ordered = cache.entries.values.sorted {
      ($0.features.createdAt, $0.features.id) < ($1.features.createdAt, $1.features.id)
    }
    await applyAnalysis(of: ordered, reset: false)
    return outcome
  }

  /// Thumbnail for a screenshot. `size` is in pixels (points × display scale).
  func thumbnail(for id: String, size: CGSize) async -> UIImage? {
    await library.thumbnail(for: id, size: size)
  }

  /// Raw features of a screenshot (Debug screen).
  func features(for id: String) -> ScreenshotFeatures? {
    featuresByID[id]
  }

  /// Capture date for display; `nil` when PhotoKit had none (REV-4).
  func captureDate(for id: String) -> Date? {
    guard let date = featuresByID[id]?.createdAt, CaptureDate.isKnown(date) else { return nil }
    return date
  }
}
