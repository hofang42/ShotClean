import CryptoKit
import Foundation

/// Feature prints stored apart from `AnalysisCache` (REV-10): one small raw `Data` file per
/// screenshot in Application Support/FeaturePrints/<sha256-of-id>.bin.
///
/// Each print is written once, when its screenshot is analyzed, and read lazily by
/// `FeaturePrintIndex` only for pairs the clusterer actually compares. The cache plist therefore
/// stays small (metadata + OCR) and is never rewritten because of prints. Files are encrypted
/// at rest (`completeUnlessOpen`) and the directory is excluded from backups. Stateless and
/// synchronous: call off the main actor.
enum FeaturePrintStore {
  private static let directoryName = "FeaturePrints"

  static func directoryURL() throws -> URL {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var directory = support.appending(path: directoryName, directoryHint: .isDirectory)
    if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
    }
    return directory
  }

  /// File name derived from the id; local identifiers contain "/" and must not be used as is.
  private static func fileURL(for id: String, in directory: URL) -> URL {
    let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appending(path: "\(digest).bin", directoryHint: .notDirectory)
  }

  /// Writes (or replaces) prints. Failures are logged; a missing print only disables
  /// near-duplicate detection for that screenshot.
  static func write(_ prints: [String: Data]) {
    guard !prints.isEmpty else { return }
    do {
      let directory = try directoryURL()
      for (id, data) in prints {
        try data.write(
          to: fileURL(for: id, in: directory),
          options: [.atomic, .completeFileProtectionUnlessOpen])
      }
    } catch {
      Log.cache.error(
        "Failed to write feature prints: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// The stored print for `id`, or `nil`.
  static func read(_ id: String) -> Data? {
    guard let directory = try? directoryURL() else { return nil }
    return try? Data(contentsOf: fileURL(for: id, in: directory))
  }

  static func remove(_ ids: some Sequence<String>) {
    guard let directory = try? directoryURL() else { return }
    for id in ids {
      try? FileManager.default.removeItem(at: fileURL(for: id, in: directory))
    }
  }

  static func removeAll() {
    guard let directory = try? directoryURL() else { return }
    do {
      try FileManager.default.removeItem(at: directory)
    } catch {
      Log.cache.debug("No feature prints removed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
