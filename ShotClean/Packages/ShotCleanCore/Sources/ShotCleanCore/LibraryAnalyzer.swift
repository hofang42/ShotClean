import Foundation

/// Combines per-image classification with library-wide duplicate and burst clustering.
///
/// Final priority per item (see `Category`):
/// `transferReceipt` > protected > `exactDuplicate` > `expiredTicket`/`expiredOrder` > `qrCode`
/// > `burstShot` > `lowQualityPhoto` > `oldScreenshot` > `utilityPhoto` > `nearDuplicate`
/// > `other`.
/// - Receipts are always `.keep`, even when duplicated.
/// - Protected assets (favorite, user album, edited) are always `.keep` (category `.other`).
/// - Exact-duplicate non-keepers → `.delete`; the keeper is judged by the other rules only.
/// - Burst non-keepers → `.delete` (`burstShot`) unless a higher-priority rule matched.
/// - Near-duplicate non-keepers → `.review` unless a higher-priority rule matched.
public struct LibraryAnalyzer: Sendable {
  public let thresholds: Thresholds

  public init(thresholds: Thresholds = .default) {
    self.thresholds = thresholds
  }

  public func analyze(
    _ features: [ScreenshotFeatures],
    distance: (String, String) -> Float?,
    now: Date
  ) -> AnalysisResult {
    let classifier = ScreenshotClassifier(thresholds: thresholds)
    let clusters = DuplicateClusterer(thresholds: thresholds)
      .clusters(features: features, distance: distance)
    let createdAt = Dictionary(
      features.map { ($0.id, $0.createdAt) }, uniquingKeysWith: { first, _ in first })

    // id → keeper id, only for non-keeper members.
    var exactKeeperOf: [String: String] = [:]
    var nearNonKeepers = Set<String>()
    var burstNonKeepers = Set<String>()
    for cluster in clusters {
      for id in cluster.memberIDs where id != cluster.keeperID {
        switch cluster.kind {
        case .exact: exactKeeperOf[id] = cluster.keeperID
        case .burst: burstNonKeepers.insert(id)
        case .near: nearNonKeepers.insert(id)
        }
      }
    }

    var verdicts: [String: Verdict] = [:]
    var order: [String] = []
    for feature in features where verdicts[feature.id] == nil {
      order.append(feature.id)
      let own = classifier.classify(feature, now: now)
      verdicts[feature.id] = finalVerdict(
        own: own,
        exactKeeperDate: exactKeeperOf[feature.id].flatMap { createdAt[$0] },
        isBurstNonKeeper: burstNonKeepers.contains(feature.id),
        isNearNonKeeper: nearNonKeepers.contains(feature.id)
      )
    }
    return AnalysisResult(verdicts: verdicts, clusters: clusters, order: order)
  }

  private func finalVerdict(
    own: Verdict, exactKeeperDate: Date?, isBurstNonKeeper: Bool, isNearNonKeeper: Bool
  ) -> Verdict {
    // Receipts and protected assets: the classifier already decided `.keep`.
    if own.category == .transferReceipt || own.suggestion == .keep { return own }
    if let keeperDate = exactKeeperDate {
      return Verdict(
        category: .exactDuplicate, suggestion: .delete,
        reason: "Giống hệt ảnh ngày \(thresholds.calendar.dayMonth(keeperDate))")
    }
    if Self.outranksBurst.contains(own.category) { return own }
    if isBurstNonKeeper {
      return Verdict(
        category: .burstShot, suggestion: .delete,
        reason: "Chụp liên tiếp — giữ lại 1 ảnh của loạt")
    }
    if own.category != .other { return own }
    if isNearNonKeeper {
      return Verdict(category: .nearDuplicate, suggestion: .review, reason: "Gần giống ảnh khác")
    }
    return own
  }

  /// Per-image categories that win over a burst.
  private static let outranksBurst: Set<Category> = [.expiredTicket, .expiredOrder, .qrCode]
}
