import Foundation

/// Groups the library into exact-duplicate, burst and near-duplicate clusters.
///
/// - exact: identical non-nil `sha256` (≥ 2 members), keeper = oldest.
/// - burst: runs of consecutive screenshots (`metadata.isScreenshot`, known capture date, not in
///   any exact cluster) whose neighbours are `≤ burstMaxGap` apart, ≥ 2 members, keeper =
///   newest (the last shot usually shows the final state). One linear pass after the sort.
/// - near: connected components over pairs with `distance < nearDupMaxDistance` and
///   capture gap `≤ nearDupMaxGap`. Exact and burst non-keepers are excluded (their keeper
///   stands in for them). Keeper = largest pixel area, ties → oldest.
/// - exact and near clusters prefer a protected member (favorite, user album, edited) as keeper.
///
/// - text: pairs of the same pixel size inside the window whose OCR token sets have Jaccard
///   similarity `≥ nearDupTextJaccard` also link (slightly scrolled screens), unless their
///   FeaturePrint distance is known and `≥ nearDupMaxMedoidDistance` (same words, clearly
///   different picture, e.g. one product page shown in two colors).
/// - drift guard: in components of 3...40 members, members clearly far from the medoid are
///   dropped.
/// - keeper tie-breaks: larger area, then larger file size, then oldest.
///
/// `distance` is only queried for pairs inside the time window (sliding window over the
/// capture-date order), so cost is O(n log n + pairs-in-window), not O(n²).
/// Output is deterministic: members sorted by `createdAt` (ties by id), clusters sorted by
/// their first member, exact before burst before near on ties.
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
    let inExact = Set(exact.flatMap(\.memberIDs))
    let burst = burstClusters(ordered.filter { !inExact.contains($0.id) }, distance: distance)
    let excluded = Set(
      (exact + burst).flatMap { cluster in cluster.memberIDs.filter { $0 != cluster.keeperID } })
    let near = nearClusters(ordered.filter { !excluded.contains($0.id) }, distance: distance)
    let byID = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let all: [(cluster: Cluster, first: ScreenshotFeatures)] = (exact + burst + near).compactMap {
      cluster in
      guard let firstID = cluster.memberIDs.first, let first = byID[firstID] else { return nil }
      return (cluster, first)
    }
    return all.sorted { lhs, rhs in
      if lhs.first.id != rhs.first.id { return Self.chronological(lhs.first, rhs.first) }
      return Self.kindRank(lhs.cluster.kind) < Self.kindRank(rhs.cluster.kind)
    }.map(\.cluster)
  }

  /// Tie order of clusters that start with the same member.
  private static func kindRank(_ kind: Cluster.Kind) -> Int {
    switch kind {
    case .exact: 0
    case .burst: 1
    case .near: 2
    }
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
    let isProtected = Set(ordered.filter(\.metadata.isProtected).map(\.id))
    return hashOrder.compactMap { hash in
      guard let members = groups[hash], members.count >= 2, let oldest = members.first else {
        return nil
      }
      let keeper = members.first(where: isProtected.contains) ?? oldest
      return Cluster(kind: .exact, memberIDs: members, keeperID: keeper)
    }
  }

  // MARK: - Burst

  /// Two text-rich shots of one burst must share at least this share of their OCR tokens.
  static let burstMinTextJaccard = 0.6

  /// `ordered` must be chronological and contain no exact-cluster member. Only screenshots with
  /// a known capture date take part; anything else in between does not break a run.
  ///
  /// Taking several *different* screens within seconds is common (scrolling through a chat or an
  /// article), and deleting all but the last would lose content. So consecutive shots only join
  /// a run when they are not clearly different: feature-print distance (when known) below
  /// `nearDupMaxMedoidDistance`, and, when both carry enough OCR text, token Jaccard of at least
  /// `burstMinTextJaccard`. Only consecutive pairs are compared, so cost stays linear.
  private func burstClusters(
    _ ordered: [ScreenshotFeatures], distance: (String, String) -> Float?
  ) -> [Cluster] {
    guard thresholds.burstMaxGap > 0 else { return [] }
    let shots = ordered.filter {
      $0.metadata.isScreenshot
        && $0.createdAt >= ScreenshotClassifier.earliestPlausibleCaptureDate
    }
    var clusters: [Cluster] = []
    var run: [ScreenshotFeatures] = []
    func flush() {
      defer { run.removeAll(keepingCapacity: true) }
      // Protected members are kept by their verdict anyway; the keeper stays the newest shot.
      guard run.count >= 2, let newest = run.last else { return }
      clusters.append(Cluster(kind: .burst, memberIDs: run.map(\.id), keeperID: newest.id))
    }
    func sameContent(_ a: ScreenshotFeatures, _ b: ScreenshotFeatures) -> Bool {
      if let d = distance(a.id, b.id), d >= thresholds.nearDupMaxMedoidDistance { return false }
      let tokensA = Self.tokens(a.text)
      let tokensB = Self.tokens(b.text)
      guard tokensA.count >= thresholds.nearDupMinTextTokens,
        tokensB.count >= thresholds.nearDupMinTextTokens
      else { return true }
      return Self.jaccard(tokensA, tokensB) >= Self.burstMinTextJaccard
    }
    for shot in shots {
      if let previous = run.last,
        shot.createdAt.timeIntervalSince(previous.createdAt) > thresholds.burstMaxGap
          || !sameContent(previous, shot)
      {
        flush()
      }
      run.append(shot)
    }
    flush()
    return clusters
  }

  // MARK: - Near

  /// `candidates` must be chronological.
  private func nearClusters(
    _ candidates: [ScreenshotFeatures],
    distance: (String, String) -> Float?
  ) -> [Cluster] {
    var components = UnionFind(count: candidates.count)
    // `nearDupTextJaccard > 1` disables the text rule: skip tokenizing the whole library.
    let usesText = thresholds.nearDupTextJaccard <= 1
    let tokens = usesText ? candidates.map { Self.tokens($0.text) } : []
    func textMatch(_ i: Int, _ j: Int) -> Bool {
      guard usesText else { return false }
      let small = min(tokens[i].count, tokens[j].count)
      let large = max(tokens[i].count, tokens[j].count)
      guard candidates[i].pixelSize == candidates[j].pixelSize,
        small >= thresholds.nearDupMinTextTokens,
        // Jaccard ≤ small / large: skips the set operations for clearly different texts.
        Double(small) >= thresholds.nearDupTextJaccard * Double(large)
      else { return false }
      return Self.jaccard(tokens[i], tokens[j]) >= thresholds.nearDupTextJaccard
    }
    // Distances already asked for, keyed `i * count + j` (i < j). The drift guard reuses them,
    // so `distance` is only ever queried inside the time window.
    var known: [Int: Float] = [:]
    let count = candidates.count
    func inWindow(_ i: Int, _ j: Int) -> Bool {
      abs(candidates[j].createdAt.timeIntervalSince(candidates[i].createdAt))
        <= thresholds.nearDupMaxGap
    }
    for i in candidates.indices {
      var j = i + 1
      while j < candidates.count,
        candidates[j].createdAt.timeIntervalSince(candidates[i].createdAt)
          <= thresholds.nearDupMaxGap
      {
        let d = distance(candidates[i].id, candidates[j].id)
        if let d { known[i * count + j] = d }
        if let d, d < thresholds.nearDupMaxDistance {
          components.union(i, j)
        } else if (d ?? 0) < thresholds.nearDupMaxMedoidDistance, textMatch(i, j) {
          // Text links only when the pictures are not clearly different (or unknown).
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
      guard let found = groups[root], found.count >= 2 else { return nil }
      let indices = dropDrifters(
        found,
        distance: { a, b in known[min(a, b) * count + max(a, b)] },
        text: { a, b in inWindow(a, b) && textMatch(a, b) })
      guard indices.count >= 2 else { return nil }
      let members = indices.map { candidates[$0] }
      // Members are chronological, so the first best is the oldest among equals.
      var keeper = members[0]
      for member in members.dropFirst() where Self.isBetterKeeper(member, than: keeper) {
        keeper = member
      }
      return Cluster(kind: .near, memberIDs: members.map(\.id), keeperID: keeper.id)
    }
  }

  /// A protected member wins, then the largest area, then the larger known file size;
  /// otherwise the earlier one stays.
  static func isBetterKeeper(_ member: ScreenshotFeatures, than keeper: ScreenshotFeatures)
    -> Bool
  {
    if member.metadata.isProtected != keeper.metadata.isProtected {
      return member.metadata.isProtected
    }
    if member.pixelSize.area != keeper.pixelSize.area {
      return member.pixelSize.area > keeper.pixelSize.area
    }
    if let a = member.fileSize, let b = keeper.fileSize { return a > b }
    return false
  }

  /// Largest component the medoid check runs on (it costs O(k²) lookups).
  private static let maxDriftCheckSize = 40

  /// Chained components can link A–B–C although A and C differ. For components of ≥ 3 members,
  /// picks the medoid (lowest mean known distance; a member without any known distance cannot
  /// be the medoid) and drops members whose known distance to it is `≥ nearDupMaxMedoidDistance`
  /// unless they text-match it. `indices` stay chronological. `distance` takes candidate
  /// indices and only knows pairs measured during linking (inside the time window).
  private func dropDrifters(
    _ indices: [Int],
    distance: (Int, Int) -> Float?,
    text: (Int, Int) -> Bool
  ) -> [Int] {
    guard indices.count >= 3, indices.count <= Self.maxDriftCheckSize else { return indices }
    var sums = [Float](repeating: 0, count: indices.count)
    var counts = [Int](repeating: 0, count: indices.count)
    var table: [[Float?]] = Array(
      repeating: Array(repeating: nil, count: indices.count), count: indices.count)
    for a in indices.indices {
      for b in indices.indices where b > a {
        guard let d = distance(indices[a], indices[b]) else {
          continue
        }
        table[a][b] = d
        table[b][a] = d
        sums[a] += d
        sums[b] += d
        counts[a] += 1
        counts[b] += 1
      }
    }
    // A plain sum would favor members with few known distances (missing prints sum to 0).
    let means = indices.indices.map { k in
      counts[k] == 0 ? Float.infinity : sums[k] / Float(counts[k])
    }
    guard var medoid = means.firstIndex(where: \.isFinite) else { return indices }
    for k in means.indices where means[k] < means[medoid] { medoid = k }
    let far = thresholds.nearDupMaxMedoidDistance
    var kept: Set<Int> = [medoid]
    var unknown: [Int] = []
    for k in indices.indices where k != medoid {
      if let d = table[medoid][k] {
        if d < far || text(indices[medoid], indices[k]) { kept.insert(k) }
      } else {
        unknown.append(k)
      }
    }
    // No known distance to the medoid: keep a member only while it still links to a kept one
    // (its original link may have been a dropped drifter).
    var grew = true
    while grew {
      grew = false
      for k in unknown where !kept.contains(k) {
        for other in kept {
          let d = table[k][other]
          let isLinked =
            (d.map { $0 < thresholds.nearDupMaxDistance } ?? false)
            || ((d ?? 0) < far && text(indices[k], indices[other]))
          if isLinked {
            kept.insert(k)
            grew = true
            break
          }
        }
      }
    }
    return indices.indices.filter { kept.contains($0) }.map { indices[$0] }
  }

  /// Normalized alphanumeric tokens (length ≥ 2) of OCR text.
  static func tokens(_ text: String) -> Set<String> {
    let folded = TextNormalizer.fold(text)
    return Set(
      folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        .filter { $0.count >= 2 })
  }

  static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
    let union = a.union(b).count
    return union == 0 ? 0 : Double(a.intersection(b).count) / Double(union)
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
