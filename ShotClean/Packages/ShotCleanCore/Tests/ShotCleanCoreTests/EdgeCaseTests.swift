import Foundation
import Testing

@testable import ShotCleanCore

/// Deterministic PRNG (SplitMix64) so shuffles are reproducible.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

@Suite("Edge cases — classifier input")
struct ClassifierInputEdgeTests {
  let classifier = ScreenshotClassifier(thresholds: TestSupport.thresholds)
  let now = TestSupport.now

  @Test("empty and whitespace-only text is .other", arguments: ["", "   ", "\n\n\t", "\u{00A0}"])
  func emptyText(text: String) {
    let verdict = classifier.classify(
      TestSupport.features("e", createdAt: TestSupport.daysAgo(400), text: text), now: now)
    #expect(verdict == .other)
  }

  @Test("empty text still allows the QR rule")
  func emptyTextWithQR() {
    let verdict = classifier.classify(
      TestSupport.features("e", createdAt: TestSupport.daysAgo(30), text: "", qr: 0.5), now: now)
    #expect(verdict.category == .qrCode)
  }

  @Test("50 KB of OCR text classifies correctly in under 50 ms")
  func hugeTextPerformance() {
    let line = "Shopee Đơn hàng đã giao 12/08/2026 Mã vận đơn SPXVN0612345678 ₫259.000 về nhà 😂\n"
    var text = ""
    while text.utf8.count < 50_000 { text += line }
    let feature = TestSupport.features("big", createdAt: TestSupport.daysAgo(2), text: text)
    // Warm up regex caches / lazy statics once, then measure.
    _ = classifier.classify(feature, now: now)
    let clock = ContinuousClock()
    var verdict = Verdict.other
    // Best of 5: a single wall-clock sample is flaky when the machine is busy (e.g. parallel builds).
    let elapsed = (0..<5).map { _ in
      clock.measure { verdict = classifier.classify(feature, now: now) }
    }.min()!
    let foldTime = clock.measure { _ = TextNormalizer.fold(text) }
    let dateTime = clock.measure {
      _ = DateExtractor.dates(in: text, reference: now, calendar: TestSupport.calendar)
    }
    print("[perf] classify 50 KB: \(elapsed) (fold \(foldTime), dates \(dateTime))")
    #expect(verdict.category == .expiredOrder)
    #expect(elapsed < .milliseconds(50))
  }

  @Test("emoji glued to keywords still matches a receipt")
  func emojiReceipt() {
    let text = "🎉Chuyển tiền thành công✅\n💸 1.000.000 VND 🇻🇳\nNgười nhận 👩‍👩‍👧 NGUYEN THI A"
    let verdict = classifier.classify(TestSupport.features("r", text: text), now: now)
    #expect(verdict.category == .transferReceipt)
  }

  @Test("mixed scripts (CJK, Thai, Cyrillic, Arabic) around an old order are handled")
  func mixedScripts() {
    let text = "淘宝 订单 已签收\nShopee🛒Đơn hàng đã giao\nสั่งซื้อ สำเร็จ\nЗаказ доставлен\nتم التوصيل"
    let verdict = classifier.classify(
      TestSupport.features("m", createdAt: TestSupport.daysAgo(45), text: text), now: now)
    #expect(verdict.category == .expiredOrder)
  }

  @Test("text made only of emoji and foreign scripts is .other")
  func onlyForeign() {
    let text = "😂🤣👍🏽❤️‍🔥 你好世界 안녕하세요 こんにちは"
    let verdict = classifier.classify(
      TestSupport.features("f", createdAt: TestSupport.daysAgo(400), text: text), now: now)
    #expect(verdict == .other)
  }

  @Test(
    "fold never crashes and keeps emoji content",
    arguments: ["👩‍👩‍👧‍👦", "🇻🇳", "e\u{301}\u{302}\u{323}", "Đ\u{0110}đ"])
  func foldOddUnicode(text: String) {
    let folded = TextNormalizer.fold(text)
    #expect(!folded.isEmpty)
    #expect(!folded.contains("đ"))
  }
}

@Suite("Edge cases — dates, boundaries, time zones")
struct BoundaryEdgeTests {
  let calendar = TestSupport.calendar

  func ticket(_ text: String, createdAt: Date, now: Date) -> Verdict {
    ScreenshotClassifier(thresholds: TestSupport.thresholds)
      .classify(TestSupport.features("t", createdAt: createdAt, text: text), now: now)
  }

  @Test("'31/12' read on 02/01 resolves to the previous year")
  func yearBoundaryExtraction() {
    let dates = DateExtractor.dates(
      in: "Vé xe 31/12 22:00", reference: TestSupport.date(2026, 1, 2), calendar: calendar)
    #expect(dates == [TestSupport.date(2025, 12, 31)])
  }

  @Test("'02/01' read on 30/12 resolves to the next year (within 60 days)")
  func yearBoundaryForward() {
    let dates = DateExtractor.dates(
      in: "Ngày đi 02/01", reference: TestSupport.date(2025, 12, 30), calendar: calendar)
    #expect(dates == [TestSupport.date(2026, 1, 2)])
  }

  @Test("upcoming New Year ticket '02/01' captured on 30/12 is not suggested for deletion")
  func yearBoundaryUpcomingTicket() {
    let verdict = ticket(
      "Vé xe Phương Trang\nGiờ khởi hành 22:00 02/01", createdAt: TestSupport.date(2025, 12, 30, 9),
      now: TestSupport.date(2025, 12, 31, 9))
    #expect(verdict == .other)
  }

  @Test("unknown capture date (.distantPast) never triggers age-based rules (REV-4)")
  func unknownCaptureDate() {
    let classifier = ScreenshotClassifier(thresholds: TestSupport.thresholds)
    let unknown = Date.distantPast
    let now = TestSupport.now
    // QR, ticket without date, order without date: all age-only → nothing.
    #expect(
      classifier.classify(TestSupport.features("q", createdAt: unknown, qr: 0.5), now: now)
        == .other)
    #expect(
      classifier.classify(
        TestSupport.features("t", createdAt: unknown, text: "Boarding pass\nFlight VJ123\nGate 5"),
        now: now) == .other)
    #expect(
      classifier.classify(
        TestSupport.features("o", createdAt: unknown, text: "Lazada\nĐang vận chuyển"), now: now)
        == .other)
    // Year-less dates are read relative to `now`, not year 0001: 20/10 is upcoming.
    #expect(
      classifier.classify(
        TestSupport.features("v", createdAt: unknown, text: "Vé xe\nKhởi hành 22:00 20/10"),
        now: now)
        == .other)
    // Explicit past dates in the text still work.
    #expect(
      classifier.classify(
        TestSupport.features("p", createdAt: unknown, text: "Vé xe\nNgày đi 01/09/2026"), now: now
      ).category == .expiredTicket)
  }

  @Test("ticket for 31/12 (no year) is expired on 02/01, captured 01/01")
  func yearBoundaryTicketExpired() {
    let verdict = ticket(
      "Vé xe Phương Trang\nGiờ khởi hành 22:00 31/12", createdAt: TestSupport.date(2026, 1, 1, 8),
      now: TestSupport.date(2026, 1, 2, 9))
    #expect(verdict.category == .expiredTicket)
    #expect(verdict.reason == "Vé ngày 31/12/2025 đã qua")
  }

  @Test("ticket for 31/12 is still in grace on 01/01")
  func yearBoundaryTicketGrace() {
    let verdict = ticket(
      "Vé xe Phương Trang\nGiờ khởi hành 22:00 31/12", createdAt: TestSupport.date(2025, 12, 20),
      now: TestSupport.date(2026, 1, 1, 23, 59))
    #expect(verdict == .other)
  }

  @Test("ticket dated today / yesterday is kept, two days ago is expired")
  func ticketDayBoundaries() {
    let now = TestSupport.date(2026, 10, 15, 23, 59, 59)
    let created = TestSupport.date(2026, 10, 1)
    #expect(ticket("Vé tàu\nNgày đi 15/10/2026", createdAt: created, now: now) == .other)
    #expect(ticket("Vé tàu\nNgày đi 14/10/2026", createdAt: created, now: now) == .other)
    #expect(
      ticket("Vé tàu\nNgày đi 13/10/2026", createdAt: created, now: now).category == .expiredTicket)
    // Right after midnight the "today" date is still not expired.
    #expect(
      ticket("Vé tàu\nNgày đi 15/10/2026", createdAt: created, now: TestSupport.date(2026, 10, 15))
        == .other)
  }

  @Test("Asia/Ho_Chi_Minh has a constant +07:00 offset and no DST transitions")
  func dstFreeTimeZone() {
    let tz = calendar.timeZone
    for month in 1...12 {
      #expect(tz.secondsFromGMT(for: TestSupport.date(2026, month, 15)) == 7 * 3600)
    }
    #expect(tz.nextDaylightSavingTimeTransition(after: TestSupport.date(2026, 1, 1)) == nil)
    let days = calendar.dateComponents(
      [.day], from: TestSupport.date(2026, 1, 1), to: TestSupport.date(2027, 1, 1)
    ).day
    #expect(days == 365)
  }

  @Test("QR age is counted in calendar days even across a DST change (America/New_York)")
  func qrAgeAcrossDST() throws {
    var ny = Calendar(identifier: .gregorian)
    ny.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let thresholds = Thresholds(calendar: ny)
    let created = try #require(
      ny.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 10)))
    let now = try #require(ny.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 10)))
    // 7 calendar days but 169 hours because clocks fall back on 01/11.
    #expect(now.timeIntervalSince(created) == 7 * 86_400 + 3600)
    let verdict = ScreenshotClassifier(thresholds: thresholds)
      .classify(TestSupport.features("q", createdAt: created, qr: 0.5), now: now)
    #expect(verdict.category == .qrCode)
    #expect(verdict.reason == "Mã QR, chụp 7 ngày trước")
  }

  @Test("qrAreaRatio exactly at the threshold qualifies; just below does not")
  func qrThreshold() {
    let classifier = ScreenshotClassifier(thresholds: TestSupport.thresholds)
    let created = TestSupport.daysAgo(10)
    let at = TestSupport.thresholds.qrMinArea
    #expect(
      classifier.classify(
        TestSupport.features("a", createdAt: created, qr: at), now: TestSupport.now
      )
      .category == .qrCode)
    #expect(
      classifier.classify(
        TestSupport.features("b", createdAt: created, qr: at.nextDown), now: TestSupport.now)
        == .other)
    #expect(
      classifier.classify(
        TestSupport.features("c", createdAt: created, qr: 1.0), now: TestSupport.now
      )
      .category == .qrCode)
  }

  @Test("QR exactly 7 days old qualifies; one second younger does not")
  func qrAgeBoundary() {
    let classifier = ScreenshotClassifier(thresholds: TestSupport.thresholds)
    let sevenDays = TestSupport.daysAgo(7)
    #expect(
      classifier.classify(
        TestSupport.features("a", createdAt: sevenDays, qr: 0.5), now: TestSupport.now)
        == Verdict(category: .qrCode, suggestion: .delete, reason: "Mã QR, chụp 7 ngày trước"))
    #expect(
      classifier.classify(
        TestSupport.features("b", createdAt: sevenDays.addingTimeInterval(1), qr: 0.5),
        now: TestSupport.now) == .other)
  }

  @Test("order exactly 30 days old is kept; one second older is expired")
  func orderAgeBoundary() {
    let classifier = ScreenshotClassifier(thresholds: TestSupport.thresholds)
    let thirty = TestSupport.date(2026, 9, 15, 10)  // now − 30 days exactly
    #expect(
      classifier.classify(
        TestSupport.features("a", createdAt: thirty, text: "Shopee đơn hàng"), now: TestSupport.now)
        == .other)
    #expect(
      classifier.classify(
        TestSupport.features(
          "b", createdAt: thirty.addingTimeInterval(-1), text: "Shopee đơn hàng"),
        now: TestSupport.now
      ).category == .expiredOrder)
  }
}

@Suite("Edge cases — clustering and analyzer at scale")
struct ScaleEdgeTests {
  /// 2,000 screenshots, one per minute, in bursts of 4 near-identical shots.
  static func syntheticLibrary(count: Int = 2_000) -> [ScreenshotFeatures] {
    let start = TestSupport.date(2026, 1, 1)
    return (0..<count).map { index in
      TestSupport.features(
        String(format: "img-%05d", index),
        createdAt: start.addingTimeInterval(Double(index) * 60),
        sha: index % 97 == 0 ? "dup-\(index % 3)" : nil)
    }
  }

  static func burst(_ id: String) -> Int {
    (Int(id.dropFirst(4)) ?? 0) / 4
  }

  @Test("2,000 items cluster quickly and distance is only queried inside the time window")
  func clustererScale() {
    var rng = SeededGenerator(seed: 42)
    let library = Self.syntheticLibrary().shuffled(using: &rng)
    let createdAt = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0.createdAt) })
    let maxGap = TestSupport.thresholds.nearDupMaxGap
    var calls = 0
    var outOfWindow = 0
    let clock = ContinuousClock()
    var clusters: [Cluster] = []
    let elapsed = clock.measure {
      clusters = DuplicateClusterer(thresholds: TestSupport.thresholds)
        .clusters(features: library) { a, b in
          calls += 1
          if let ta = createdAt[a], let tb = createdAt[b], abs(ta.timeIntervalSince(tb)) > maxGap {
            outOfWindow += 1
          }
          return Self.burst(a) == Self.burst(b) ? 0.1 : 0.9
        }
    }
    print("[perf] cluster 2,000 items: \(elapsed), distance calls: \(calls)")
    #expect(outOfWindow == 0)
    // One shot per minute and a 10-minute window → at most 10 later neighbours each.
    #expect(calls > 0)
    #expect(calls <= 2_000 * 10)
    #expect(calls < 2_000 * 1_999 / 2 / 50, "should be far below all pairs")
    #expect(elapsed < .seconds(2))
    let near = clusters.filter { $0.kind == .near }
    #expect(near.count == 500)
    #expect(near.allSatisfy { $0.memberIDs.count == 4 || $0.memberIDs.count == 3 })
  }

  /// Mixed library: receipts, tickets, orders, QR, exact and near duplicates.
  static func mixedLibrary() -> [ScreenshotFeatures] {
    var items: [ScreenshotFeatures] = []
    let base = TestSupport.date(2026, 8, 1)
    for index in 0..<200 {
      let at = base.addingTimeInterval(Double(index) * 120)
      let id = "m-\(index)"
      switch index % 6 {
      case 0:
        items.append(
          TestSupport.features(
            id, createdAt: at, text: "MB\nGiao dịch thành công\n500.000 VND", sha: "r\(index % 4)"))
      case 1:
        items.append(TestSupport.features(id, createdAt: at, text: "Vé xe\nNgày đi 02/08/2026"))
      case 2:
        items.append(TestSupport.features(id, createdAt: at, text: "Shopee đơn hàng đã giao"))
      case 3:
        items.append(TestSupport.features(id, createdAt: at, qr: 0.4, sha: "q\(index % 5)"))
      default:
        items.append(TestSupport.features(id, createdAt: at, width: 1000 + index % 3))
      }
    }
    // Same timestamp ties to exercise id tie-breaking.
    items.append(TestSupport.features("tie-b", createdAt: base, sha: "tie"))
    items.append(TestSupport.features("tie-a", createdAt: base, sha: "tie"))
    return items
  }

  static func distance(_ a: String, _ b: String) -> Float? {
    // Symmetric, order-independent pseudo distance.
    let key = [a, b].sorted().joined(separator: "|")
    let hash = key.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
    return Float(hash % 100) / 100
  }

  @Test("analyzer output is identical for any input order")
  func analyzerDeterminism() {
    let library = Self.mixedLibrary()
    let analyzer = LibraryAnalyzer(thresholds: TestSupport.thresholds)
    let reference = analyzer.analyze(library, distance: Self.distance, now: TestSupport.now)
    #expect(!reference.clusters.isEmpty)
    var rng = SeededGenerator(seed: 7)
    for _ in 0..<5 {
      let shuffled = library.shuffled(using: &rng)
      let result = analyzer.analyze(shuffled, distance: Self.distance, now: TestSupport.now)
      #expect(result.verdicts == reference.verdicts)
      #expect(result.clusters == reference.clusters)
      #expect(result.preselectedForDeletion() == reference.preselectedForDeletion())
      for category in ShotCleanCore.Category.allCases {
        #expect(Set(result.ids(in: category)) == Set(reference.ids(in: category)))
      }
    }
  }

  @Test("tied timestamps pick the keeper by id, independent of input order")
  func tieBreak() {
    let library = Self.mixedLibrary()
    let a = DuplicateClusterer(thresholds: TestSupport.thresholds)
      .clusters(features: library, distance: { _, _ in nil })
    let b = DuplicateClusterer(thresholds: TestSupport.thresholds)
      .clusters(features: library.reversed(), distance: { _, _ in nil })
    #expect(a == b)
    let tie = a.first { $0.memberIDs.contains("tie-a") }
    #expect(tie?.keeperID == "tie-a")
  }
}
