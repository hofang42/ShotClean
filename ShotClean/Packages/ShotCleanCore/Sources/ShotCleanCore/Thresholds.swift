import Foundation

/// Every tunable number used by the rules lives here.
///
/// `calendar` is also part of the thresholds: it decides what "a day" is, how dates without a
/// year are interpreted and how dates are printed in reasons (`dd/MM/yyyy`). The default is a
/// Gregorian calendar in `Asia/Ho_Chi_Minh`, because the app targets Vietnamese users and tests
/// must be deterministic. The app may pass `Calendar.current` (forced to Gregorian) instead.
public struct Thresholds: Sendable, Equatable {
  /// Minimum total QR area / image area for the `qrCode` rule.
  public var qrMinArea: Double
  /// Minimum age (whole days) before a QR screenshot is suggested for deletion.
  public var qrMinAgeDays: Int
  /// A ticket expires when its latest date is earlier than `startOfToday - ticketGraceDays`.
  public var ticketGraceDays: Int
  /// Order screenshots older than this many days (by capture date or by text date) expire.
  public var orderMaxAgeDays: Int
  /// FeaturePrint distance strictly below this means "near duplicate".
  public var nearDupMaxDistance: Float
  /// Maximum capture time gap (seconds) between two near duplicates.
  public var nearDupMaxGap: TimeInterval
  /// A member of a near-duplicate cluster with ≥ 3 members whose FeaturePrint distance to the
  /// cluster medoid is known and `≥` this value is dropped (prevents chained-cluster drift).
  public var nearDupMaxMedoidDistance: Float
  /// Minimum Jaccard similarity of OCR token sets for text-based near duplicates
  /// (same screen scrolled slightly). `> 1` disables the text rule.
  public var nearDupTextJaccard: Double
  /// Both screenshots need at least this many OCR tokens for the text rule to apply.
  public var nearDupMinTextTokens: Int
  /// Calendar used for day arithmetic, year inference and formatting.
  public var calendar: Calendar

  public init(
    qrMinArea: Double = 0.15,
    qrMinAgeDays: Int = 7,
    ticketGraceDays: Int = 1,
    orderMaxAgeDays: Int = 30,
    nearDupMaxDistance: Float = 0.35,
    nearDupMaxGap: TimeInterval = 600,
    nearDupMaxMedoidDistance: Float = 0.6,
    nearDupTextJaccard: Double = 0.85,
    nearDupMinTextTokens: Int = 15,
    calendar: Calendar = Thresholds.vietnameseCalendar
  ) {
    self.qrMinArea = qrMinArea
    self.qrMinAgeDays = qrMinAgeDays
    self.ticketGraceDays = ticketGraceDays
    self.orderMaxAgeDays = orderMaxAgeDays
    self.nearDupMaxDistance = nearDupMaxDistance
    self.nearDupMaxGap = nearDupMaxGap
    self.nearDupMaxMedoidDistance = nearDupMaxMedoidDistance
    self.nearDupTextJaccard = nearDupTextJaccard
    self.nearDupMinTextTokens = nearDupMinTextTokens
    self.calendar = calendar
  }

  public static let `default` = Thresholds()

  /// Gregorian calendar in the `Asia/Ho_Chi_Minh` time zone (UTC+7, no DST).
  public static var vietnameseCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone =
      TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? TimeZone(secondsFromGMT: 7 * 3600) ?? .gmt
    return calendar
  }
}
