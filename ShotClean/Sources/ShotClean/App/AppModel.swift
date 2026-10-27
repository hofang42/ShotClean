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
  /// Total number of scanned assets visible to the app (the "/ 3.800" in S4): screenshots, plus
  /// camera photos when `settings.scanCameraPhotos` is on.
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
  /// Live metadata (favorite, edited, album, screenshot) from the latest library fetch. Applied
  /// to cached features before every classification; never part of cache validity.
  @ObservationIgnored private var metadataByID: [String: MetadataFlags] = [:]
  /// Favorites, user-album members and edited assets: never preselected.
  @ObservationIgnored private var protectedIDs: Set<String> = []
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
      // Nothing changed in Photos since the last fetch: skip refetching the whole library.
      guard LibraryChangeMonitor.shared.consumeChange() else { return }
      let includePhotos = settings.scanCameraPhotos
      let fetched = await Task.detached(priority: .utility) {
        ScreenshotLibrary.fetchAssets(includePhotos: includePhotos)
      }.value
      let assets = fetched.filter { !deletedIDs.contains($0.id) }
      let modified = cache.map { cache in
        assets.contains { cache.entries[$0.id] != nil && cache.validEntry(for: $0) == nil }
      } ?? false
      if assets.count != screenshotCount || modified {
        await rescan(full: false)
      } else if updateMetadata(from: assets) {
        // Favorites / albums / edits changed in Photos: protection must apply right away.
        await reclassifyCached()
      }
    }
  }

  /// Stores the live metadata of `assets`. Returns whether anything changed.
  @discardableResult
  private func updateMetadata(from assets: [ScreenshotAsset]) -> Bool {
    let fresh = Dictionary(
      assets.map { ($0.id, $0.metadata) }, uniquingKeysWith: { first, _ in first })
    guard fresh != metadataByID else { return false }
    metadataByID = fresh
    return true
  }

  /// Reclassifies the cached analyses, keeping the user's choices. No-op without a cache.
  private func reclassifyCached() async {
    guard let cache else { return }
    let ordered = cache.entries.values.sorted {
      ($0.features.createdAt, $0.features.id) < ($1.features.createdAt, $1.features.id)
    }
    // Nothing published yet: there are no user choices to keep, start from the preselection.
    let hasResult = result != nil
    await applyAnalysis(of: ordered, reset: !hasResult, reapply: hasResult)
  }

  /// Shortcuts hook (`shotclean://clean`, opened by the user or by an automation the user made
  /// in the Shortcuts app; the app never schedules anything itself). Waits for any running scan,
  /// runs an incremental scan, and returns the quick-clean ids (the overview's "Dọn nhanh").
  /// Empty when onboarding or photo access is missing.
  func prepareQuickClean() async -> Set<String> {
    guard hasCompletedOnboarding, ScreenshotLibrary.currentAccess().canRead else { return [] }
    if scanTask == nil { await rescan(full: false) }
    // A launch or foreground scan may have replaced ours; wait until all of them are done.
    while let running = scanTask {
      await running.value
      if scanTask == running { break }
    }
    return quickCleanIDs
  }

  /// Ids "Dọn nhanh" deletes: the preselection, minus anything the user deselected.
  var quickCleanIDs: Set<String> {
    selection.intersection(preselectedIDs)
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

    let includePhotos = settings.scanCameraPhotos
    // Changes from here on mark the library dirty for the next foreground check.
    LibraryChangeMonitor.shared.startIfNeeded()
    _ = LibraryChangeMonitor.shared.consumeChange()
    let fetched = await Task.detached(priority: .userInitiated) {
      ScreenshotLibrary.fetchAssets(includePhotos: includePhotos)
    }.value
    let assets = fetched.filter { !deletedIDs.contains($0.id) }
    screenshotCount = assets.count
    let metadataChanged = updateMetadata(from: assets)
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
      "Scan: \(assets.count) assets, \(pending.count) to analyze, full=\(full, privacy: .public)"
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
    // Changed live metadata (favorite, album, edit) always reclassifies: protection is a rule.
    if full || !pending.isEmpty || !pruned.isEmpty || !hadResult || metadataChanged {
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
    // Live metadata wins over the snapshot stored with the analysis.
    let liveMetadata = metadataByID
    let features = entries.map { entry -> ScreenshotFeatures in
      var copy = entry.features
      if let metadata = liveMetadata[copy.id] { copy.metadata = metadata }
      return copy
    }
    let analysis = await Task.detached(priority: .userInitiated) {
      AppModel.classify(features, now: now, thresholds: thresholds)
    }.value
    // A newer analysis (e.g. after a deletion) started meanwhile; it wins.
    guard generation == analysisGeneration else { return }

    featuresByID = Dictionary(
      features.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var sizes: [String: Int64] = [:]
    var undated: Set<String> = []
    var protected: Set<String> = []
    for feature in features {
      if let size = feature.fileSize { sizes[feature.id] = size }
      if !CaptureDate.isKnown(feature.createdAt) { undated.insert(feature.id) }
      if feature.metadata.isProtected { protected.insert(feature.id) }
    }
    self.sizes = sizes
    result = analysis

    undatedIDs = undated
    protectedIDs = protected
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
    _ features: [ScreenshotFeatures], now: Date, thresholds: Thresholds
  ) -> AnalysisResult {
    // REV-10: prints are read lazily, only for the pairs the clusterer compares.
    let index = FeaturePrintIndex(load: FeaturePrintStore.read)
    return LibraryAnalyzer(thresholds: thresholds).analyze(
      features,
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

  /// Keeper picked by `settings.keeperRule` (duplicates) or the Core (bursts: newest). Receipts
  /// win, then protected assets, so they are never the ones deleted.
  private func defaultKeeper(of cluster: Cluster) -> String {
    let members = cluster.memberIDs
    if let receipt = members.first(where: {
      result?.verdicts[$0]?.category == .transferReceipt
    }) {
      return receipt
    }
    if cluster.kind == .burst { return cluster.keeperID }
    if let protected = members.first(where: protectedIDs.contains) {
      return protected
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
  /// - Favorites, user-album members and edited assets are never preselected.
  /// - Only enabled categories; receipts never.
  /// - Bursts follow `.burstShot`: everyone but the keeper (newest).
  /// - Duplicate clusters follow the keeper rule: everyone but the default keeper.
  /// - A member matched by another rule (receipt, expired ticket…) keeps that rule's say.
  /// - Order independent: a keeper of any enabled cluster is never picked by the cluster pass,
  ///   even when it is a non-keeper of an overlapping cluster (exact keeper inside a near one).
  private func preselection(for analysis: AnalysisResult) -> Set<String> {
    let enabled = settings.enabledCategories
    // Exact-duplicate and burst verdicts are decided below with the keeper, not by the Core.
    let byRule = analysis.preselectedForDeletion().filter { id in
      guard let category = analysis.verdicts[id]?.category,
        category != .exactDuplicate, category != .burstShot
      else {
        return false
      }
      return enabled.contains(category)
    }
    var byCluster: Set<String> = []
    var keepers: Set<String> = []
    for cluster in analysis.clusters {
      let kindEnabled: Bool
      // Verdicts the cluster pass may override; any other rule keeps its own say.
      let clusterCategories: Set<ShotCleanCore.Category>
      switch cluster.kind {
      case .exact:
        kindEnabled = enabled.contains(.exactDuplicate)
        clusterCategories = [.exactDuplicate, .nearDuplicate, .other]
      case .burst:
        kindEnabled = enabled.contains(.burstShot)
        clusterCategories = [.burstShot, .other]
      case .near:
        kindEnabled = enabled.contains(.nearDuplicate) && settings.preselectNearDuplicates
        clusterCategories = [.exactDuplicate, .nearDuplicate, .other]
      }
      guard kindEnabled else { continue }
      let keeper = defaultKeeper(of: cluster)
      keepers.insert(keeper)
      for id in cluster.memberIDs where id != keeper {
        // A member matched by another rule keeps that rule's say; `.keep` (protected) never.
        guard let verdict = analysis.verdicts[id], verdict.suggestion != .keep else { continue }
        if clusterCategories.contains(verdict.category) {
          byCluster.insert(id)
        }
      }
    }
    return byRule.union(byCluster.subtracting(keepers))
      .subtracting(undatedIDs)
      .subtracting(protectedIDs)
  }

  /// Applies new rules: saves them and reclassifies the cached analyses (no rescan). Turning
  /// camera-photo scanning on or off changes what is fetched: incremental rescan instead.
  func updateSettings(_ newSettings: CleanupSettings) async {
    guard newSettings != settings else { return }
    let scopeChanged = newSettings.scanCameraPhotos != settings.scanCameraPhotos
    settings = newSettings
    newSettings.save(to: defaults)
    if scopeChanged, hasCompletedOnboarding, ScreenshotLibrary.currentAccess().canRead {
      await rescan(full: false)
      return
    }
    // No cache yet (first scan running): that scan classifies with the new settings.
    await reclassifyCached()
  }

  /// The user picks a new keeper: it is deselected. For exact duplicates and bursts the previous
  /// keeper is selected instead, unless it is a receipt or protected. Near duplicates are never
  /// auto-selected.
  func setKeeper(_ newKeeper: String, in cluster: Cluster) {
    let oldKeeper = keeper(of: cluster)
    let oldIsReceipt = result?.verdicts[oldKeeper]?.category == .transferReceipt
    let selectsPrevious =
      cluster.kind != .near && !oldIsReceipt && !protectedIDs.contains(oldKeeper)
    selectionState.setKeeper(
      newKeeper, coreKeeperID: cluster.keeperID, members: cluster.memberIDs,
      defaultKeeper: defaultKeeper(of: cluster),
      selectPreviousKeeper: selectsPrevious)
  }

  /// Favorite, in a user album or edited: never preselected or bulk-selected.
  func isProtected(_ id: String) -> Bool {
    protectedIDs.contains(id)
  }

  /// Whether a bulk action (select all, drag-select, one-tap category or cluster actions) may
  /// select `id`. Receipts, protected (favorite / album / edited) and undated assets never are;
  /// they can still be picked one by one.
  func isBulkSelectable(_ id: String) -> Bool {
    guard let verdict = result?.verdicts[id] else { return false }
    return verdict.category != .transferReceipt && verdict.suggestion != .keep
      && !protectedIDs.contains(id) && !undatedIDs.contains(id)
  }

  /// Ids a one-tap "select the whole category" selects: every bulk-selectable member, and for
  /// duplicate / burst categories every cluster member except the cluster's keeper.
  func bulkSelectableIDs(in category: ShotCleanCore.Category) -> Set<String> {
    guard let result, category != .transferReceipt else { return [] }
    let kind: Cluster.Kind? =
      switch category {
      case .exactDuplicate: .exact
      case .nearDuplicate: .near
      case .burstShot: .burst
      default: nil
      }
    guard let kind else { return Set(result.ids(in: category).filter(isBulkSelectable)) }
    var ids: Set<String> = []
    for cluster in result.clusters where cluster.kind == kind {
      let keeperID = keeper(of: cluster)
      ids.formUnion(cluster.memberIDs.filter { $0 != keeperID && isBulkSelectable($0) })
    }
    return ids
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
