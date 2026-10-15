import Foundation

/// Capture-date conventions shared with the Core (REV-4).
///
/// PhotoKit can return `nil` for `creationDate`. The app then passes `unknown` to the Core, whose
/// classifier treats any date before 2000-01-01 as unknown and skips every age-based rule. The app
/// additionally never preselects such screenshots and never shows the sentinel date.
enum CaptureDate {
  /// Sentinel for a missing creation date. Also sorts first, so an undated copy is the keeper
  /// (never the deleted one) of an exact-duplicate cluster.
  static let unknown = Date.distantPast

  /// Mirrors `ScreenshotClassifier.earliestPlausibleCaptureDate` in ShotCleanCore (not public).
  static let earliestPlausible = Date(timeIntervalSince1970: 946_684_800)  // 2000-01-01 UTC

  static func isKnown(_ date: Date) -> Bool {
    date >= earliestPlausible
  }
}
