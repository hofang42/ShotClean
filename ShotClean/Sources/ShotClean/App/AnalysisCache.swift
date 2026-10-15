import Foundation
import ShotCleanCore

/// Everything the app learned about one screenshot. Stored in `AnalysisCache`.
struct AnalyzedScreenshot: Sendable, Codable, Equatable {
  let features: ScreenshotFeatures
  /// `PHAsset.modificationDate` at analysis time; a different value invalidates the entry.
  let modificationDate: Date?
  /// `NSKeyedArchiver` data of a `VNFeaturePrintObservation`, `nil` when Vision failed.
  let featurePrint: Data?
  /// When the analysis was done from a low-quality local thumbnail or without a hash (original
  /// in iCloud only); `nil` for a full-quality analysis. Degraded entries are shown and retried
  /// only when the asset changes, on a full rescan, or after `AnalysisCache.degradedRetryInterval`
  /// (REV-5, NEW-1) — never on every scan.
  let degradedAt: Date?

  var isDegraded: Bool { degradedAt != nil }
}

/// On-disk cache of analysis results keyed by `PHAsset.localIdentifier`.
///
/// Stored as a binary property list in Application Support, encrypted at rest
/// (`completeUnlessOpen`) and excluded from backups (OCR text must never leave the device).
/// Value type: load and save off the main actor.
struct AnalysisCache: Sendable, Codable {
  /// 3: `degradedAt` (NEW-1); 2: pinned feature-print revision 2, hash of the edited rendition
  /// (REV-3/5/12).
  static let formatVersion = 3
  /// Minimum time before a degraded entry of an unchanged asset is analyzed again (NEW-1).
  static let degradedRetryInterval: TimeInterval = 24 * 60 * 60
  private static let fileName = "AnalysisCache.plist"

  enum LoadResult: Sendable {
    /// The stored cache, or an empty one when the file is missing, outdated or corrupt.
    case loaded(AnalysisCache)
    /// The file exists but cannot be read right now (e.g. data protection while locked).
    /// Callers must not overwrite it (REV-14).
    case unavailable
  }

  private struct VersionProbe: Decodable {
    let version: Int
  }

  private(set) var version = AnalysisCache.formatVersion
  var entries: [String: AnalyzedScreenshot] = [:]

  init() {}

  /// The cached entry for `asset`, or `nil` when missing or stale (asset modified since).
  func validEntry(for asset: ScreenshotAsset) -> AnalyzedScreenshot? {
    guard let entry = entries[asset.id], entry.modificationDate == asset.modificationDate else {
      return nil
    }
    return entry
  }

  /// Whether `asset` must be (re)analyzed: missing or stale (modified since), or degraded and
  /// last tried at least `degradedRetryInterval` before `now`.
  func needsAnalysis(_ asset: ScreenshotAsset, now: Date) -> Bool {
    guard let entry = validEntry(for: asset) else { return true }
    guard let degradedAt = entry.degradedAt else { return false }
    return now.timeIntervalSince(degradedAt) >= Self.degradedRetryInterval
  }

  /// Drops entries whose asset no longer exists (deleted, or hidden by limited access).
  /// Returns whether anything was dropped.
  @discardableResult
  mutating func prune(keeping ids: Set<String>) -> Bool {
    let before = entries.count
    entries = entries.filter { ids.contains($0.key) }
    return entries.count != before
  }

  mutating func remove(_ ids: Set<String>) {
    for id in ids { entries[id] = nil }
  }

  // MARK: Persistence

  static func fileURL() throws -> URL {
    let directory = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return directory.appending(path: fileName, directoryHint: .notDirectory)
  }

  /// Loads the cache. Missing, outdated or undecodable → empty cache; unreadable → `.unavailable`.
  static func load() -> LoadResult {
    let url: URL
    let data: Data
    do {
      url = try fileURL()
      guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return .loaded(AnalysisCache())
      }
      data = try Data(contentsOf: url)
    } catch {
      Log.cache.error("Cache file unreadable: \(error.localizedDescription, privacy: .public)")
      return .unavailable
    }
    do {
      let probe = try PropertyListDecoder().decode(VersionProbe.self, from: data)
      guard probe.version == formatVersion else {
        Log.cache.notice("Cache format \(probe.version) is outdated, starting fresh")
        return .loaded(AnalysisCache())
      }
      let cache = try PropertyListDecoder().decode(AnalysisCache.self, from: data)
      Log.cache.info("Loaded \(cache.entries.count) cached analyses")
      return .loaded(cache)
    } catch {
      Log.cache.error(
        "Cache file corrupt, starting fresh: \(error.localizedDescription, privacy: .public)")
      return .loaded(AnalysisCache())
    }
  }

  func save() throws {
    var url = try Self.fileURL()
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(self)
    // REV-14: readable while the app has it open after first unlock, still encrypted at rest.
    try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
    Log.cache.info("Saved \(entries.count) analyses (\(data.count) bytes)")
  }

  static func deleteFile() {
    do {
      try FileManager.default.removeItem(at: try fileURL())
    } catch {
      Log.cache.debug("No cache file removed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
