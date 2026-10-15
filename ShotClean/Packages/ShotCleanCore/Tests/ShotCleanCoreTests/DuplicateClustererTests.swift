import Foundation
import Testing

@testable import ShotCleanCore

/// Symmetric distance table for tests; unknown pairs are "very far".
struct DistanceTable {
  private var values: [Set<String>: Float] = [:]

  init(_ pairs: [(String, String, Float)]) {
    for (a, b, d) in pairs { values[[a, b]] = d }
  }

  func callAsFunction(_ a: String, _ b: String) -> Float? {
    values[[a, b]] ?? 1.0
  }
}

/// Counts distance calls without crossing concurrency boundaries.
final class CallCounter {
  var count = 0
}

@Suite("DuplicateClusterer")
struct DuplicateClustererTests {
  let clusterer = DuplicateClusterer(thresholds: TestSupport.thresholds)
  let base = TestSupport.date(2026, 10, 1, 9)

  func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

  @Test("exact clusters group identical sha256, keeper is the oldest")
  func exactClusters() {
    let features = [
      TestSupport.features("c", createdAt: at(30), sha: "h1"),
      TestSupport.features("a", createdAt: at(0), sha: "h1"),
      TestSupport.features("b", createdAt: at(10), sha: "h1"),
      TestSupport.features("d", createdAt: at(5), sha: "h2"),
      TestSupport.features("e", createdAt: at(6), sha: nil),
      TestSupport.features("f", createdAt: at(7), sha: nil),
    ]
    let clusters = clusterer.clusters(features: features, distance: { _, _ in nil })
    #expect(clusters == [Cluster(kind: .exact, memberIDs: ["a", "b", "c"], keeperID: "a")])
  }

  @Test("exact duplicates are found regardless of time gap")
  func exactIgnoresTimeGap() {
    let features = [
      TestSupport.features("a", createdAt: at(0), sha: "h"),
      TestSupport.features("b", createdAt: at(60 * 24 * 90), sha: "h"),
    ]
    let clusters = clusterer.clusters(features: features, distance: { _, _ in nil })
    #expect(clusters.map(\.memberIDs) == [["a", "b"]])
  }

  @Test("near duplicates chain through connected components")
  func nearChain() {
    let features = [
      TestSupport.features("a", createdAt: at(0)),
      TestSupport.features("b", createdAt: at(4)),
      TestSupport.features("c", createdAt: at(8)),
    ]
    let table = DistanceTable([("a", "b", 0.1), ("b", "c", 0.2), ("a", "c", 0.9)])
    let clusters = clusterer.clusters(features: features, distance: table.callAsFunction)
    #expect(clusters.count == 1)
    #expect(clusters.first?.kind == .near)
    #expect(clusters.first?.memberIDs == ["a", "b", "c"])
  }

  @Test("near duplicates must be within the time window")
  func nearTimeWindow() {
    let features = [
      TestSupport.features("a", createdAt: at(0)),
      TestSupport.features("b", createdAt: at(10)),  // exactly 600 s → allowed
      TestSupport.features("c", createdAt: at(30)),  // 20 min after b → not allowed
    ]
    let table = DistanceTable([("a", "b", 0.1), ("b", "c", 0.1), ("a", "c", 0.1)])
    let clusters = clusterer.clusters(features: features, distance: table.callAsFunction)
    #expect(clusters.map(\.memberIDs) == [["a", "b"]])
  }

  @Test("distance must be strictly below the threshold; nil means unknown")
  func nearThreshold() {
    let features = [
      TestSupport.features("a", createdAt: at(0)),
      TestSupport.features("b", createdAt: at(1)),
      TestSupport.features("c", createdAt: at(2)),
    ]
    let clusters = clusterer.clusters(features: features) { a, b in
      Set([a, b]) == ["a", "b"] ? 0.35 : nil
    }
    #expect(clusters.isEmpty)
  }

  @Test("near keeper is the largest image, ties go to the oldest")
  func nearKeeper() {
    let bigger = [
      TestSupport.features("a", createdAt: at(0), width: 1170, height: 2532),
      TestSupport.features("b", createdAt: at(1), width: 1290, height: 2796),
    ]
    let tie = [
      TestSupport.features("x", createdAt: at(1)),
      TestSupport.features("y", createdAt: at(0)),
    ]
    #expect(clusterer.clusters(features: bigger) { _, _ in 0.1 }.first?.keeperID == "b")
    #expect(clusterer.clusters(features: tie) { _, _ in 0.1 }.first?.keeperID == "y")
  }

  @Test("exact non-keepers are excluded from near clusters, exact keepers are not")
  func nearExcludesExactMembers() {
    let features = [
      TestSupport.features("k", createdAt: at(0), sha: "h"),
      TestSupport.features("dup", createdAt: at(1), sha: "h"),
      TestSupport.features("n", createdAt: at(2)),
    ]
    let counter = CallCounter()
    let clusters = clusterer.clusters(features: features) { a, b in
      counter.count += 1
      #expect(a != "dup" && b != "dup")
      return 0.1
    }
    #expect(
      clusters == [
        Cluster(kind: .exact, memberIDs: ["k", "dup"], keeperID: "k"),
        Cluster(kind: .near, memberIDs: ["k", "n"], keeperID: "k"),
      ])
    #expect(counter.count == 1)
  }

  @Test("distance is only queried for pairs inside the time window")
  func avoidsQuadraticDistanceCalls() {
    // 200 screenshots one hour apart: no pair is inside the 10-minute window.
    let features = (0..<200).map { TestSupport.features("p\($0)", createdAt: at(Double($0) * 60)) }
    let counter = CallCounter()
    let clusters = clusterer.clusters(features: features) { _, _ in
      counter.count += 1
      return 0
    }
    #expect(clusters.isEmpty)
    #expect(counter.count == 0)
  }

  @Test("clusters are ordered by their first member's capture date")
  func deterministicOrder() {
    let features = [
      TestSupport.features("late1", createdAt: at(500), sha: "h1"),
      TestSupport.features("late2", createdAt: at(501), sha: "h1"),
      TestSupport.features("n1", createdAt: at(100)),
      TestSupport.features("n2", createdAt: at(101)),
      TestSupport.features("early1", createdAt: at(0), sha: "h2"),
      TestSupport.features("early2", createdAt: at(1000), sha: "h2"),
    ]
    let table = DistanceTable([("n1", "n2", 0.05)])
    let clusters = clusterer.clusters(features: features, distance: table.callAsFunction)
    #expect(
      clusters.map(\.memberIDs) == [["early1", "early2"], ["n1", "n2"], ["late1", "late2"]])
  }

  @Test("empty input yields no clusters")
  func empty() {
    #expect(clusterer.clusters(features: []) { _, _ in 0 }.isEmpty)
  }
}
