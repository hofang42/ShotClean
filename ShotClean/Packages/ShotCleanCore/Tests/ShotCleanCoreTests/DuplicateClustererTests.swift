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

  @Test("drift guard drops a member far from the medoid")
  func driftGuard() {
    let features = [
      TestSupport.features("a", createdAt: at(0)),
      TestSupport.features("b", createdAt: at(1)),
      TestSupport.features("c", createdAt: at(2)),
    ]
    // Medoid is b (sum 0.40); c is 0.30 from it, which is ≥ 0.3 → dropped.
    let table = DistanceTable([("a", "b", 0.1), ("b", "c", 0.3), ("a", "c", 0.34)])
    let strict = DuplicateClusterer(
      thresholds: Thresholds(
        nearDupMaxMedoidDistance: 0.3, calendar: TestSupport.thresholds.calendar))
    let clusters = strict.clusters(features: features, distance: table.callAsFunction)
    #expect(clusters.map(\.memberIDs) == [["a", "b"]])
  }

  @Test("text near duplicates link same-size screens with similar OCR")
  func textNearDuplicate() {
    let words = (0..<20).map { "word\($0)" }
    let t1 = words.joined(separator: " ")
    let t2 = (words.dropLast() + ["extra"]).joined(separator: " ")
    let features = [
      TestSupport.features("a", createdAt: at(0), text: t1),
      TestSupport.features("b", createdAt: at(1), text: t2),
      TestSupport.features("c", createdAt: at(2), text: "short text"),
    ]
    let clusters = clusterer.clusters(features: features) { _, _ in nil }
    #expect(clusters.map(\.memberIDs) == [["a", "b"]])
  }

  @Test("same text but a clearly different picture does not link")
  func textNeedsSimilarPicture() {
    let text = (0..<20).map { "word\($0)" }.joined(separator: " ")
    let features = [
      TestSupport.features("a", createdAt: at(0), text: text),
      TestSupport.features("b", createdAt: at(1), text: text),
    ]
    #expect(clusterer.clusters(features: features) { _, _ in 0.9 }.isEmpty)
    #expect(clusterer.clusters(features: features) { _, _ in 0.5 }.count == 1)
  }

  @Test("text rule needs the same pixel size and enough tokens")
  func textRuleGuards() {
    let text = (0..<20).map { "word\($0)" }.joined(separator: " ")
    let resized = [
      TestSupport.features("a", createdAt: at(0), text: text),
      TestSupport.features("b", createdAt: at(1), text: text, width: 1179, height: 2556),
    ]
    #expect(clusterer.clusters(features: resized) { _, _ in nil }.isEmpty)
    let short = [
      TestSupport.features("a", createdAt: at(0), text: "chat ok"),
      TestSupport.features("b", createdAt: at(1), text: "chat ok"),
    ]
    #expect(clusterer.clusters(features: short) { _, _ in nil }.isEmpty)
  }

  @Test("drift guard ignores members without known distances when picking the medoid")
  func driftGuardMissingPrints() {
    let words = (0..<20).map { "word\($0)" }
    let features = [
      TestSupport.features("a", createdAt: at(0)),
      TestSupport.features("b", createdAt: at(1)),
      TestSupport.features("c", createdAt: at(2), text: words.joined(separator: " ")),
      TestSupport.features("d", createdAt: at(3), text: words.joined(separator: " ")),
    ]
    // c–d link by text only (d has no print). d must not become the medoid (old sum = 0);
    // b is. c is far from b and dropped; d only linked through c, so it goes too.
    let table = DistanceTable([("a", "b", 0.1), ("b", "c", 0.3), ("a", "c", 0.34)])
    let strict = DuplicateClusterer(
      thresholds: Thresholds(
        nearDupMaxMedoidDistance: 0.3, calendar: TestSupport.thresholds.calendar))
    let clusters = strict.clusters(features: features) { a, b in
      a == "d" || b == "d" ? nil : table(a, b)
    }
    #expect(clusters.map(\.memberIDs) == [["a", "b"]])
  }

  @Test("near keeper tie on area prefers the larger file")
  func keeperFileSize() {
    let features = [
      TestSupport.features("a", createdAt: at(0), fileSize: 100),
      TestSupport.features("b", createdAt: at(1), fileSize: 500),
    ]
    #expect(clusterer.clusters(features: features) { _, _ in 0.1 }.first?.keeperID == "b")
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
