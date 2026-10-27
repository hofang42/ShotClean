import Foundation

@testable import ShotCleanCore

/// Shared deterministic clock/calendar for all tests: Gregorian, Asia/Ho_Chi_Minh.
enum TestSupport {
  static let calendar = Thresholds.vietnameseCalendar
  static let thresholds = Thresholds(calendar: calendar)

  /// "Now" for every test: 15/10/2026 10:00 (UTC+7).
  static let now = date(2026, 10, 15, 10)

  static func date(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
  ) -> Date {
    let components = DateComponents(
      year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    guard let date = calendar.date(from: components) else {
      preconditionFailure("invalid test date \(components)")
    }
    return date
  }

  static func daysAgo(_ days: Double) -> Date {
    now.addingTimeInterval(-days * 86_400)
  }

  static func features(
    _ id: String,
    createdAt: Date = TestSupport.daysAgo(1),
    text: String = "",
    qr: Double = 0,
    sha: String? = nil,
    width: Int = 1170,
    height: Int = 2532,
    fileSize: Int64? = nil,
    metadata: MetadataFlags = MetadataFlags(),
    luma: Double? = nil,
    sharpness: Double? = nil,
    aesthetics: Double? = nil,
    isUtility: Bool? = nil
  ) -> ScreenshotFeatures {
    ScreenshotFeatures(
      id: id,
      createdAt: createdAt,
      pixelSize: PixelSize(width: width, height: height),
      fileSize: fileSize,
      text: text,
      qrAreaRatio: qr,
      sha256: sha,
      metadata: metadata,
      meanLuma: luma,
      sharpness: sharpness,
      aestheticsScore: aesthetics,
      isUtility: isUtility
    )
  }

  /// Metadata of a plain, unprotected screenshot.
  static let screenshot = MetadataFlags(isScreenshot: true)
  /// Metadata of a plain, unprotected camera photo.
  static let photo = MetadataFlags()
}
