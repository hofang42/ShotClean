import Foundation
import ShotCleanCore

/// Everything the app learned about one screenshot. Stored in `AnalysisCache`.
struct AnalyzedScreenshot: Sendable, Codable, Equatable {
  let features: ScreenshotFeatures
  /// `PHAsset.modificationDate` at analysis time; a different value invalidates the entry.
  let modificationDate: Date?
  /// `NSKeyedArchiver` data of a `VNFeaturePrintObservation`, `nil` when Vision failed.
  let featurePrint: Data?
}

/// On-disk cache of analysis results keyed by `PHAsset.localIdentifier`.
///
/// Stored as a binary property list in Application Support with complete file protection and
/// excluded from backups (OCR text must never leave the device). Value type: load and save
/// off the main actor.
struct AnalysisCache: Sendable, Codable {
  static let formatVersion = 1
  private static let fileName = "AnalysisCache.plist"

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

  /// Drops entries whose asset no longer exists (deleted, or hidden by limited access).
  mutating func prune(keeping ids: Set<String>) {
    entries = entries.filter { ids.contains($0.key) }
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

  /// Loads the cache; returns an empty cache when the file is missing, unreadable or outdated.
  static func load() -> AnalysisCache {
    do {
      let url = try fileURL()
      guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return AnalysisCache()
      }
      let data = try Data(contentsOf: url)
      let cache = try PropertyListDecoder().decode(AnalysisCache.self, from: data)
      guard cache.version == formatVersion else {
        Log.cache.notice("Cache format \(cache.version) is outdated, starting fresh")
        return AnalysisCache()
      }
      Log.cache.info("Loaded \(cache.entries.count) cached analyses")
      return cache
    } catch {
      Log.cache.error("Failed to load cache: \(error.localizedDescription, privacy: .public)")
      return AnalysisCache()
    }
  }

  func save() throws {
    var url = try Self.fileURL()
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(self)
    try data.write(to: url, options: [.atomic, .completeFileProtection])
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
