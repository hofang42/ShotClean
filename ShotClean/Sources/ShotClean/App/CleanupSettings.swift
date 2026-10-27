import Foundation
import ShotCleanCore

/// User-tunable cleanup rules (S9). Persisted as JSON in `UserDefaults`; every change
/// reclassifies the cached analyses, no rescan needed.
struct CleanupSettings: Codable, Equatable, Sendable {
  /// Which member of a duplicate cluster is kept by default.
  enum KeeperRule: String, Codable, CaseIterable, Sendable {
    /// Exact: oldest · near: largest pixel area (the Core rule).
    case automatic
    case oldest
    case newest
    /// Largest file on disk (usually the sharpest rendition).
    case largestFile
  }

  var qrMinAgeDays = 7
  var ticketGraceDays = 1
  var orderMaxAgeDays = 30
  /// FeaturePrint distance below which two screenshots are "near duplicates".
  var nearDupMaxDistance: Double = 0.35
  var nearDupMaxGapMinutes = 10
  var keeperRule = KeeperRule.automatic
  /// Near-duplicate non-keepers are preselected for deletion too.
  var preselectNearDuplicates = false
  /// Categories whose suggestions are preselected and queued for swipe review. Receipts are
  /// never part of this.
  var enabledCategories: Set<ShotCleanCore.Category> = CleanupSettings.filterableCategories

  static let filterableCategories: Set<ShotCleanCore.Category> = [
    .exactDuplicate, .expiredTicket, .expiredOrder, .qrCode, .nearDuplicate,
  ]

  static let `default` = CleanupSettings()

  var thresholds: Thresholds {
    Thresholds(
      qrMinAgeDays: qrMinAgeDays,
      ticketGraceDays: ticketGraceDays,
      orderMaxAgeDays: orderMaxAgeDays,
      nearDupMaxDistance: Float(nearDupMaxDistance),
      nearDupMaxGap: TimeInterval(nearDupMaxGapMinutes * 60)
    )
  }

  // Tolerant decoding: settings saved by an older build keep working when fields are added.
  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = CleanupSettings()
    func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
    qrMinAgeDays = value(.qrMinAgeDays, fallback.qrMinAgeDays)
    ticketGraceDays = value(.ticketGraceDays, fallback.ticketGraceDays)
    orderMaxAgeDays = value(.orderMaxAgeDays, fallback.orderMaxAgeDays)
    nearDupMaxDistance = value(.nearDupMaxDistance, fallback.nearDupMaxDistance)
    nearDupMaxGapMinutes = value(.nearDupMaxGapMinutes, fallback.nearDupMaxGapMinutes)
    keeperRule = value(.keeperRule, fallback.keeperRule)
    preselectNearDuplicates = value(.preselectNearDuplicates, fallback.preselectNearDuplicates)
    // Stored data is not trusted: receipts can never become a preselectable category, and
    // numbers stay inside the ranges the settings screen offers.
    enabledCategories = value(.enabledCategories, fallback.enabledCategories)
      .intersection(Self.filterableCategories)
    qrMinAgeDays = min(max(qrMinAgeDays, 0), 365)
    ticketGraceDays = min(max(ticketGraceDays, 0), 30)
    orderMaxAgeDays = min(max(orderMaxAgeDays, 1), 365)
    nearDupMaxDistance =
      nearDupMaxDistance.isFinite
      ? min(max(nearDupMaxDistance, 0.15), 0.6) : fallback.nearDupMaxDistance
    nearDupMaxGapMinutes = min(max(nearDupMaxGapMinutes, 1), 120)
  }

  private static let key = "cleanupSettings"

  static func load(from defaults: UserDefaults) -> CleanupSettings {
    guard let data = defaults.data(forKey: key),
      let settings = try? JSONDecoder().decode(CleanupSettings.self, from: data)
    else { return .default }
    return settings
  }

  func save(to defaults: UserDefaults) {
    if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
  }
}
