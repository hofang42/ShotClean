import Foundation
import ShotCleanCore

/// User-tunable cleanup rules (S9). Persisted as JSON in `UserDefaults`; every change
/// reclassifies the cached analyses, no rescan needed — except `scanCameraPhotos`, which changes
/// what is fetched and triggers an incremental rescan.
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
  /// Screenshots matching no other rule are suggested for deletion after this many days.
  /// Conservative default: a quarter of a year, so recent reference screenshots stay.
  var oldScreenshotMinAgeDays = 90
  /// Screenshots taken at most this many seconds apart form a burst.
  var burstMaxGapSeconds = 8
  /// Also scan camera / saved photos for junk (blurry, dark, duplicates). Changing it rescans.
  var scanCameraPhotos = true
  var keeperRule = KeeperRule.automatic
  /// Near-duplicate non-keepers are preselected for deletion too.
  var preselectNearDuplicates = false
  /// Categories whose suggestions are preselected and queued for swipe review. Receipts are
  /// never part of this.
  var enabledCategories: Set<ShotCleanCore.Category> = CleanupSettings.filterableCategories
  /// Filterable categories this build knew when the settings were saved. A category added by a
  /// later version is enabled once on upgrade (its default), then the user's choice sticks.
  private var knownCategories: Set<ShotCleanCore.Category> = CleanupSettings.filterableCategories

  /// Review-only categories (`nearDuplicate`, `utilityPhoto`) only feed the swipe queue; they
  /// are never preselected by rule.
  static let filterableCategories: Set<ShotCleanCore.Category> = [
    .exactDuplicate, .expiredTicket, .expiredOrder, .qrCode, .nearDuplicate, .burstShot,
    .oldScreenshot, .lowQualityPhoto, .utilityPhoto,
  ]

  /// Filterable categories of v1.1, assumed known when stored settings predate the field.
  private static let v11Categories: Set<ShotCleanCore.Category> = [
    .exactDuplicate, .expiredTicket, .expiredOrder, .qrCode, .nearDuplicate,
  ]

  static let oldScreenshotAgeRange = 7...365
  static let burstGapRange = 2...30

  static let `default` = CleanupSettings()

  /// One-tap rule sets on the settings screen. A preset sets every threshold, the enabled
  /// categories and near-duplicate preselection; scan scope and the keeper rule are personal
  /// choices and stay as they are.
  enum Preset: String, CaseIterable, Identifiable, Sendable {
    /// No near-duplicate preselection, old screenshots after 180 days, camera junk
    /// (`lowQualityPhoto`) review-only.
    case cautious
    /// The defaults.
    case balanced
    /// Near duplicates preselected, old screenshots after 30 days.
    case aggressive

    var id: Self { self }
  }

  /// `self` with the rules of `preset`; scope, keeper rule and bookkeeping are kept.
  func applying(_ preset: Preset) -> CleanupSettings {
    let base = CleanupSettings()
    var settings = self
    settings.qrMinAgeDays = base.qrMinAgeDays
    settings.ticketGraceDays = base.ticketGraceDays
    settings.orderMaxAgeDays = base.orderMaxAgeDays
    settings.nearDupMaxDistance = base.nearDupMaxDistance
    settings.nearDupMaxGapMinutes = base.nearDupMaxGapMinutes
    settings.oldScreenshotMinAgeDays = base.oldScreenshotMinAgeDays
    settings.burstMaxGapSeconds = base.burstMaxGapSeconds
    settings.preselectNearDuplicates = base.preselectNearDuplicates
    settings.enabledCategories = base.enabledCategories
    switch preset {
    case .cautious:
      settings.preselectNearDuplicates = false
      settings.oldScreenshotMinAgeDays = 180
      settings.enabledCategories.remove(.lowQualityPhoto)
    case .balanced:
      break
    case .aggressive:
      settings.preselectNearDuplicates = true
      settings.oldScreenshotMinAgeDays = 30
    }
    return settings
  }

  /// The preset whose rules equal these settings, `nil` for a custom mix.
  var preset: Preset? {
    Preset.allCases.first { applying($0) == self }
  }

  var thresholds: Thresholds {
    Thresholds(
      qrMinAgeDays: qrMinAgeDays,
      ticketGraceDays: ticketGraceDays,
      orderMaxAgeDays: orderMaxAgeDays,
      nearDupMaxDistance: Float(nearDupMaxDistance),
      nearDupMaxGap: TimeInterval(nearDupMaxGapMinutes * 60),
      oldScreenshotMinAgeDays: oldScreenshotMinAgeDays,
      burstMaxGap: TimeInterval(burstMaxGapSeconds)
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
    oldScreenshotMinAgeDays = value(.oldScreenshotMinAgeDays, fallback.oldScreenshotMinAgeDays)
    burstMaxGapSeconds = value(.burstMaxGapSeconds, fallback.burstMaxGapSeconds)
    scanCameraPhotos = value(.scanCameraPhotos, fallback.scanCameraPhotos)
    // Categories added since these settings were saved start enabled (their default).
    let known = value(.knownCategories, Self.v11Categories)
    let added = fallback.enabledCategories.subtracting(known)
    // Stored data is not trusted: receipts can never become a preselectable category, and
    // numbers stay inside the ranges the settings screen offers.
    enabledCategories = value(.enabledCategories, fallback.enabledCategories)
      .union(added)
      .intersection(Self.filterableCategories)
    knownCategories = Self.filterableCategories
    qrMinAgeDays = min(max(qrMinAgeDays, 0), 365)
    ticketGraceDays = min(max(ticketGraceDays, 0), 30)
    orderMaxAgeDays = min(max(orderMaxAgeDays, 1), 365)
    nearDupMaxDistance =
      nearDupMaxDistance.isFinite
      ? min(max(nearDupMaxDistance, 0.15), 0.6) : fallback.nearDupMaxDistance
    nearDupMaxGapMinutes = min(max(nearDupMaxGapMinutes, 1), 120)
    oldScreenshotMinAgeDays = min(
      max(oldScreenshotMinAgeDays, Self.oldScreenshotAgeRange.lowerBound),
      Self.oldScreenshotAgeRange.upperBound)
    burstMaxGapSeconds = min(
      max(burstMaxGapSeconds, Self.burstGapRange.lowerBound), Self.burstGapRange.upperBound)
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
