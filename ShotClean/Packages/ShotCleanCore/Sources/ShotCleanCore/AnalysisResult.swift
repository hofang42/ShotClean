import Foundation

/// Output of `LibraryAnalyzer.analyze`.
public struct AnalysisResult: Sendable {
  /// id → final verdict.
  public let verdicts: [String: Verdict]
  public let clusters: [Cluster]
  /// Ids in analyzer input order; used to give `ids(in:)` a stable order.
  private let order: [String]

  /// Builds a result; ids are ordered lexicographically. The analyzer uses input order.
  public init(verdicts: [String: Verdict], clusters: [Cluster]) {
    self.init(verdicts: verdicts, clusters: clusters, order: verdicts.keys.sorted())
  }

  init(verdicts: [String: Verdict], clusters: [Cluster], order: [String]) {
    self.verdicts = verdicts
    self.clusters = clusters
    self.order = order
  }

  /// Ids whose final category is `category`, in analyzer input order.
  public func ids(in category: Category) -> [String] {
    order.filter { verdicts[$0]?.category == category }
  }

  /// Ids suggested for deletion (`.delete` only): exact-duplicate and burst non-keepers,
  /// expired tickets/orders, old QR codes, old screenshots and low-quality photos. Never
  /// contains receipts, protected assets (they are `.keep`), review-only categories (near
  /// duplicates, utility photos, important-looking old screenshots) or `.other`.
  public func preselectedForDeletion() -> Set<String> {
    Set(
      verdicts.compactMap { id, verdict in
        verdict.suggestion == .delete
          && !Self.neverPreselected.contains(verdict.category)
          ? id : nil
      })
  }

  /// Categories that are never preselected, whatever their suggestion.
  private static let neverPreselected: Set<Category> = [
    .transferReceipt, .nearDuplicate, .utilityPhoto, .other,
  ]

  /// Sum of `sizes` for `ids`; unknown ids count as 0.
  public func reclaimableBytes(_ ids: Set<String>, sizes: [String: Int64]) -> Int64 {
    ids.reduce(0) { $0 + (sizes[$1] ?? 0) }
  }
}
