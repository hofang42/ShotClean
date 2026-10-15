import Foundation

/// Combines per-image classification with library-wide duplicate clustering.
///
/// Final priority per screenshot:
/// `transferReceipt` > `exactDuplicate` > `expiredTicket`/`expiredOrder` > `qrCode`
/// > `nearDuplicate` > `other`.
/// - Receipts are always `.keep`, even when duplicated.
/// - Exact-duplicate non-keepers → `.delete`; the keeper is judged by the other rules only.
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
    for cluster in clusters {
      for id in cluster.memberIDs where id != cluster.keeperID {
        switch cluster.kind {
        case .exact: exactKeeperOf[id] = cluster.keeperID
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
        isNearNonKeeper: nearNonKeepers.contains(feature.id)
      )
    }
    return AnalysisResult(verdicts: verdicts, clusters: clusters, order: order)
  }

  private func finalVerdict(own: Verdict, exactKeeperDate: Date?, isNearNonKeeper: Bool)
    -> Verdict
  {
    if own.category == .transferReceipt { return own }
    if let keeperDate = exactKeeperDate {
      return Verdict(
        category: .exactDuplicate, suggestion: .delete,
        reason: "Giống hệt ảnh ngày \(thresholds.calendar.dayMonth(keeperDate))")
    }
    if own.category != .other { return own }
    if isNearNonKeeper {
      return Verdict(category: .nearDuplicate, suggestion: .review, reason: "Gần giống ảnh khác")
    }
    return own
  }
}
