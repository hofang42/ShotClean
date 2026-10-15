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
/// - Returning from Settings (E1): call `start()` again when the scene becomes active.
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
  /// id → file size in bytes, only for screenshots whose original was hashed on device.
  private(set) var sizes: [String: Int64] = [:]
  /// Ids currently selected for deletion.
  var selection: Set<String> = []
  /// Ids to review in swipe mode (S7): `.delete` then `.review` suggestions, by category priority.
  var swipeQueue: [String] = []

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
  @ObservationIgnored private var featuresByID: [String: ScreenshotFeatures] = [:]
  @ObservationIgnored private var scanTask: Task<Void, Never>?

  private static let onboardingKey = "hasCompletedOnboarding"

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

  /// Extends a limited selection with the system picker, then rescans incrementally.
  func presentLimitedLibraryPicker() async {
    await library.presentLimitedLibraryPicker()
    await rescan(full: false)
  }

  // MARK: Scanning

  /// Scans screenshots. `full == false` analyzes only assets missing from the cache;
  /// `full == true` discards the cache first. Waits for any running scan to stop.
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
    var cache: AnalysisCache
    if full {
      cache = AnalysisCache()
      await Task.detached(priority: .utility) { AnalysisCache.deleteFile() }.value
    } else if let loaded = self.cache {
      cache = loaded
    } else {
      cache = await Task.detached(priority: .userInitiated) { AnalysisCache.load() }.value
    }

    let assets = await Task.detached(priority: .userInitiated) {
      ScreenshotLibrary.fetchScreenshots()
    }.value
    screenshotCount = assets.count
    cache.prune(keeping: Set(assets.map(\.id)))
    let pending = assets.filter { cache.validEntry(for: $0) == nil }
    Log.app.info("Scan: \(assets.count) screenshots, \(pending.count) to analyze, full=\(full)")

    // Show cached results right away; the scan continues behind them.
    if !full, result == nil, !cache.entries.isEmpty {
      await applyAnalysis(of: entries(of: cache, in: assets), resetSelection: true)
    }

    let total = pending.count
    phase = .scanning(done: 0, total: total)
    if !pending.isEmpty {
      let output = await analyzer.analyze(pending) { [weak self] done in
        await self?.reportProgress(done: done, total: total)
      }
      for entry in output.analyzed { cache.entries[entry.features.id] = entry }
      unavailableIDs = Set(output.unavailableIDs)
    } else {
      unavailableIDs = []
    }

    self.cache = cache
    await persist(cache)
    await applyAnalysis(of: entries(of: cache, in: assets), resetSelection: true)
    phase = .ready
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
    do {
      try await Task.detached(priority: .utility) { try cache.save() }.value
    } catch {
      Log.cache.error("Failed to save cache: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: Analysis

  private func applyAnalysis(of entries: [AnalyzedScreenshot], resetSelection: Bool) async {
    let now = Date()
    let analysis = await Task.detached(priority: .userInitiated) {
      AppModel.classify(entries, now: now)
    }.value

    featuresByID = Dictionary(
      entries.map { ($0.features.id, $0.features) }, uniquingKeysWith: { first, _ in first })
    var sizes: [String: Int64] = [:]
    for entry in entries {
      if let size = entry.features.fileSize { sizes[entry.features.id] = size }
    }
    self.sizes = sizes
    result = analysis

    if resetSelection {
      selection = analysis.preselectedForDeletion()
      swipeQueue = Self.swipeOrder(for: analysis)
    } else {
      selection = selection.filter { featuresByID[$0] != nil }
      swipeQueue = swipeQueue.filter { featuresByID[$0] != nil }
    }
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

  // MARK: Actions

  /// Deletes `ids` after the iOS confirmation dialog (one dialog per batch). Deleted photos go to
  /// "Recently Deleted". Returns the number deleted; `0` if the user cancelled the dialog.
  func delete(_ ids: Set<String>) async throws -> Int {
    let deleted = try await ScreenshotLibrary.deleteAssets(withIDs: Array(ids))
    guard deleted > 0 else { return 0 }

    if var cache {
      cache.remove(ids)
      self.cache = cache
      await persist(cache)
    }
    screenshotCount = max(0, screenshotCount - deleted)
    unavailableIDs.subtract(ids)
    selection.subtract(ids)
    swipeQueue.removeAll { ids.contains($0) }
    let remaining = (cache?.entries.values).map(Array.init) ?? []
    let ordered = remaining.sorted {
      ($0.features.createdAt, $0.features.id) < ($1.features.createdAt, $1.features.id)
    }
    await applyAnalysis(of: ordered, resetSelection: false)
    return deleted
  }

  /// Thumbnail for a screenshot. `size` is in pixels (points × display scale).
  func thumbnail(for id: String, size: CGSize) async -> UIImage? {
    await library.thumbnail(for: id, size: size)
  }

  /// Raw features of a screenshot (Debug screen).
  func features(for id: String) -> ScreenshotFeatures? {
    featuresByID[id]
  }
}
