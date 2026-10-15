import Foundation

/// Groups the library into exact-duplicate and near-duplicate clusters.
///
/// - exact: identical non-nil `sha256` (≥ 2 members), keeper = oldest.
/// - near: connected components over pairs with `distance < nearDupMaxDistance` and
///   capture gap `≤ nearDupMaxGap`. Exact non-keepers are excluded (their keeper stands in
///   for them). Keeper = largest pixel area, ties → oldest.
///
/// `distance` is only queried for pairs inside the time window (sliding window over the
/// capture-date order), so cost is O(n log n + pairs-in-window), not O(n²).
/// Output is deterministic: members sorted by `createdAt` (ties by id), clusters sorted by
/// their first member, exact before near on ties.
public struct DuplicateClusterer: Sendable {
  public let thresholds: Thresholds

  public init(thresholds: Thresholds = .default) {
    self.thresholds = thresholds
  }

  public func clusters(
    features: [ScreenshotFeatures],
    distance: (String, String) -> Float?
  ) -> [Cluster] {
    let ordered = features.sorted(by: Self.chronological)
    let exact = exactClusters(ordered)
    let excluded = Set(
      exact.flatMap { cluster in cluster.memberIDs.filter { $0 != cluster.keeperID } })
    let near = nearClusters(ordered.filter { !excluded.contains($0.id) }, distance: distance)
    let byID = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let all: [(cluster: Cluster, first: ScreenshotFeatures)] = (exact + near).compactMap {
      cluster in
      guard let firstID = cluster.memberIDs.first, let first = byID[firstID] else { return nil }
      return (cluster, first)
    }
    return all.sorted { lhs, rhs in
      if lhs.first.id != rhs.first.id { return Self.chronological(lhs.first, rhs.first) }
      return lhs.cluster.kind == .exact && rhs.cluster.kind == .near
    }.map(\.cluster)
  }

  // MARK: - Exact

  /// `ordered` must be chronological.
  private func exactClusters(_ ordered: [ScreenshotFeatures]) -> [Cluster] {
    var groups: [String: [String]] = [:]
    var hashOrder: [String] = []
    for feature in ordered {
      guard let hash = feature.sha256, !hash.isEmpty else { continue }
      if groups[hash] == nil { hashOrder.append(hash) }
      groups[hash, default: []].append(feature.id)
    }
    return hashOrder.compactMap { hash in
      guard let members = groups[hash], members.count >= 2, let keeper = members.first else {
        return nil
      }
      return Cluster(kind: .exact, memberIDs: members, keeperID: keeper)
    }
  }

  // MARK: - Near

  /// `candidates` must be chronological.
  private func nearClusters(
    _ candidates: [ScreenshotFeatures],
    distance: (String, String) -> Float?
  ) -> [Cluster] {
    var components = UnionFind(count: candidates.count)
    for i in candidates.indices {
      var j = i + 1
      while j < candidates.count,
        candidates[j].createdAt.timeIntervalSince(candidates[i].createdAt)
          <= thresholds.nearDupMaxGap
      {
        if let d = distance(candidates[i].id, candidates[j].id), d < thresholds.nearDupMaxDistance {
          components.union(i, j)
        }
        j += 1
      }
    }

    var groups: [Int: [Int]] = [:]
    var rootOrder: [Int] = []
    for index in candidates.indices {
      let root = components.find(index)
      if groups[root] == nil { rootOrder.append(root) }
      groups[root, default: []].append(index)
    }

    return rootOrder.compactMap { root in
      guard let indices = groups[root], indices.count >= 2 else { return nil }
      let members = indices.map { candidates[$0] }
      // Members are chronological, so the first maximum is the oldest among the largest.
      var keeper = members[0]
      for member in members.dropFirst() where member.pixelSize.area > keeper.pixelSize.area {
        keeper = member
      }
      return Cluster(kind: .near, memberIDs: members.map(\.id), keeperID: keeper.id)
    }
  }

  // MARK: - Helpers

  static func chronological(_ lhs: ScreenshotFeatures, _ rhs: ScreenshotFeatures) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return lhs.id < rhs.id
  }
}

/// Disjoint-set forest with path compression and union by size.
private struct UnionFind {
  private var parent: [Int]
  private var size: [Int]

  init(count: Int) {
    parent = Array(0..<count)
    size = Array(repeating: 1, count: count)
  }

  mutating func find(_ x: Int) -> Int {
    var root = x
    while parent[root] != root { root = parent[root] }
    var node = x
    while parent[node] != root {
      let next = parent[node]
      parent[node] = root
      node = next
    }
    return root
  }

  mutating func union(_ a: Int, _ b: Int) {
    var rootA = find(a)
    var rootB = find(b)
    guard rootA != rootB else { return }
    if size[rootA] < size[rootB] { swap(&rootA, &rootB) }
    parent[rootB] = rootA
    size[rootA] += size[rootB]
  }
}
