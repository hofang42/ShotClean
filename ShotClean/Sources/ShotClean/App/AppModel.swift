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

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let library = ScreenshotLibrary()
  @ObservationIgnored private let analyzer = ScreenshotAnalyzer(maxConcurrentTasks: 2)
  @ObservationIgnored private var cache: AnalysisCache?
  /// `false` when the cache file exists but could not be read; it must not be overwritten.
  @ObservationIgnored private var canPersistCache = true
  @ObservationIgnored private var featuresByID: [String: ScreenshotFeatures] = [:]
  @ObservationIgnored private var scanTask: Task<Void, Never>?
  /// Ids deleted this session. A scan that started before a deletion never brings them back (REV-6).
  @ObservationIgnored private var deletedIDs: Set<String> = []
  /// Bumped by every `applyAnalysis`; an older, slower classification never overwrites a newer one.
  @ObservationIgnored private var analysisGeneration = 0

  private static let onboardingKey = "hasCompletedOnboarding"
  /// Assets analyzed per chunk; the cache is checkpointed between chunks (REV-7).
  private static let chunkSize = 100
  private static let checkpointInterval: Duration = .seconds(30)

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
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

    library.forget()
    let fetched = await Task.detached(priority: .userInitiated) {
      ScreenshotLibrary.fetchScreenshots()
    }.value
    let assets = fetched.filter { !deletedIDs.contains($0.id) }
    screenshotCount = assets.count
    let pruned = cache.prune(keeping: Set(assets.map(\.id)))
    let pending = assets.filter { cache.needsAnalysis($0) }
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
      for entry in output.analyzed where !deletedIDs.contains(entry.features.id) {
        cache.entries[entry.features.id] = entry
      }
      unavailable.formUnion(output.unavailableIDs)
      done += chunk.count
      // REV-7: checkpoint, so a killed app does not lose minutes of work.
      if clock.now - lastCheckpoint >= Self.checkpointInterval {
        cache.remove(deletedIDs)
        await persist(cache)
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
    if full || !pending.isEmpty || pruned || !hadResult {
      await persist(cache)
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

  private func persist(_ cache: AnalysisCache) async {
    guard canPersistCache else { return }
    do {
      try await Task.detached(priority: .utility) { try cache.save() }.value
    } catch {
      Log.cache.error("Failed to save cache: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: Analysis

  /// Classifies `entries` off the main actor and publishes the result. `reset` starts the
  /// selection over (first result, full rescan); otherwise the user's choices are merged in.
  private func applyAnalysis(of entries: [AnalyzedScreenshot], reset: Bool) async {
    analysisGeneration += 1
    let generation = analysisGeneration
    let now = Date()
    let analysis = await Task.detached(priority: .userInitiated) {
      AppModel.classify(entries, now: now)
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

    // REV-4: a screenshot without a capture date is never preselected.
    let preselected = analysis.preselectedForDeletion().subtracting(undated)
    let known = Set(featuresByID.keys)
    if reset {
      selectionState.reset(knownIDs: known, preselected: preselected)
    } else {
      selectionState.merge(knownIDs: known, preselected: preselected)
    }
    swipeQueue = Self.swipeOrder(for: analysis)
  }

  /// Runs `LibraryAnalyzer` with a feature-print distance. Off the main actor.
  nonisolated private static func classify(_ entries: [AnalyzedScreenshot], now: Date)
    -> AnalysisResult
  {
    var archives: [String: Data] = [:]
    for entry in entries {
      if let print = entry.featurePrint { archives[entry.features.id] = print }
    }
    let index = FeaturePrintIndex(archives: archives)
    return LibraryAnalyzer().analyze(
      entries.map(\.features),
      distance: { index.distance($0, $1) },
      now: now
    )
  }

  private static func swipeOrder(for analysis: AnalysisResult) -> [String] {
    let suggested: (Verdict.Suggestion) -> [String] = { suggestion in
      ShotCleanCore.Category.allCases.flatMap { category in
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

  /// Keeper shown for `cluster`: the user's choice if any, else the Core keeper (REV-9).
  func keeper(of cluster: Cluster) -> String {
    selectionState.keeper(forCoreKeeper: cluster.keeperID, members: cluster.memberIDs)
  }

  /// The user picks a new keeper: it is deselected. For exact duplicates the previous keeper is
  /// selected instead, unless it is a receipt. Near duplicates are never auto-selected.
  func setKeeper(_ newKeeper: String, in cluster: Cluster) {
    let oldKeeper = keeper(of: cluster)
    let oldIsReceipt = result?.verdicts[oldKeeper]?.category == .transferReceipt
    selectionState.setKeeper(
      newKeeper, coreKeeperID: cluster.keeperID, members: cluster.memberIDs,
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
    screenshotCount = max(0, screenshotCount - removedCount)
    unavailableIDs.subtract(ids)
    selectionState.remove(ids)
    swipeQueue.removeAll { ids.contains($0) }
    // During the very first scan there is no in-memory cache yet; that scan drops `deletedIDs`
    // and publishes the reconciled result when it ends.
    guard var cache else { return outcome }
    cache.remove(ids)
    self.cache = cache
    await persist(cache)
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
