import Foundation
import Testing

@testable import ShotCleanCore

@Suite("LibraryAnalyzer")
struct LibraryAnalyzerTests {
  let analyzer = LibraryAnalyzer(thresholds: TestSupport.thresholds)
  let now = TestSupport.now
  let base = TestSupport.date(2026, 9, 1, 9)

  func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

  func analyze(_ features: [ScreenshotFeatures], distance: DistanceTable = DistanceTable([]))
    -> AnalysisResult
  {
    analyzer.analyze(features, distance: distance.callAsFunction, now: now)
  }

  @Test("exact duplicate non-keepers are deleted with the keeper's date")
  func exactDuplicateDeleted() {
    let result = analyze([
      TestSupport.features("a", createdAt: TestSupport.date(2026, 10, 3, 8), sha: "h"),
      TestSupport.features("b", createdAt: TestSupport.date(2026, 10, 4, 8), sha: "h"),
    ])
    #expect(
      result.verdicts["b"]
        == Verdict(
          category: .exactDuplicate, suggestion: .delete, reason: "Giống hệt ảnh ngày 03/10"))
    #expect(result.verdicts["a"] == .other)
    #expect(result.preselectedForDeletion() == ["b"])
  }

  @Test("receipts are kept even when they are exact duplicates")
  func receiptDuplicateKept() {
    let result = analyze([
      TestSupport.features("r1", createdAt: at(0), text: OCRSample.vietcombankTransfer, sha: "h"),
      TestSupport.features("r2", createdAt: at(1), text: OCRSample.vietcombankTransfer, sha: "h"),
    ])
    #expect(result.verdicts["r1"]?.category == .transferReceipt)
    #expect(result.verdicts["r2"]?.category == .transferReceipt)
    #expect(result.verdicts["r2"]?.suggestion == .keep)
    #expect(result.preselectedForDeletion().isEmpty)
    #expect(result.clusters.count == 1)
  }

  @Test("exact keeper is still evaluated by the per-image rules")
  func exactKeeperFallsThroughToRules() {
    let result = analyze([
      TestSupport.features("q1", createdAt: at(0), qr: 0.5, sha: "h"),
      TestSupport.features("q2", createdAt: at(1), qr: 0.5, sha: "h"),
    ])
    #expect(result.verdicts["q1"]?.category == .qrCode)
    #expect(result.verdicts["q2"]?.category == .exactDuplicate)
    #expect(result.preselectedForDeletion() == ["q1", "q2"])
  }

  @Test("exact duplicate beats expired ticket for non-keepers")
  func exactBeatsTicket() {
    let result = analyze([
      TestSupport.features("t1", createdAt: at(0), text: OCRSample.vietjetBoardingPass, sha: "h"),
      TestSupport.features("t2", createdAt: at(1), text: OCRSample.vietjetBoardingPass, sha: "h"),
    ])
    #expect(result.verdicts["t1"]?.category == .expiredTicket)
    #expect(result.verdicts["t2"]?.category == .exactDuplicate)
  }

  @Test("near duplicate non-keepers are sent to review and never preselected")
  func nearDuplicateReview() {
    let result = analyze(
      [
        TestSupport.features("n1", createdAt: at(0), width: 1290, height: 2796),
        TestSupport.features("n2", createdAt: at(2)),
      ],
      distance: DistanceTable([("n1", "n2", 0.1)]))
    #expect(
      result.verdicts["n2"]
        == Verdict(category: .nearDuplicate, suggestion: .review, reason: "Gần giống ảnh khác"))
    #expect(result.verdicts["n1"] == .other)
    #expect(result.preselectedForDeletion().isEmpty)
    #expect(result.ids(in: .nearDuplicate) == ["n2"])
  }

  @Test("QR beats near duplicate")
  func qrBeatsNear() {
    let result = analyze(
      [
        TestSupport.features("n1", createdAt: at(0), width: 1290, height: 2796),
        TestSupport.features("n2", createdAt: at(2), qr: 0.4),
      ],
      distance: DistanceTable([("n1", "n2", 0.1)]))
    #expect(result.verdicts["n2"]?.category == .qrCode)
  }

  @Test("receipt in a near cluster stays a kept receipt")
  func receiptBeatsNear() {
    let result = analyze(
      [
        TestSupport.features("big", createdAt: at(0), width: 1290, height: 2796),
        TestSupport.features("r", createdAt: at(1), text: OCRSample.mbBankTransfer),
      ],
      distance: DistanceTable([("big", "r", 0.1)]))
    #expect(result.verdicts["r"]?.suggestion == .keep)
  }

  @Test("preselection only contains delete suggestions, never receipts or near duplicates")
  func preselectionInvariant() {
    let features = [
      TestSupport.features(
        "receipt", createdAt: at(0), text: OCRSample.techcombankTransfer, qr: 0.5),
      TestSupport.features("ticket", createdAt: at(100), text: OCRSample.busTicket),
      TestSupport.features("order", createdAt: at(200), text: OCRSample.shopeeDeliveredOrder),
      TestSupport.features("qr", createdAt: at(300), qr: 0.6),
      TestSupport.features("near1", createdAt: at(400), width: 1290, height: 2796),
      TestSupport.features("near2", createdAt: at(401)),
      TestSupport.features("chat", createdAt: at(500), text: OCRSample.randomChat),
    ]
    let result = analyze(features, distance: DistanceTable([("near1", "near2", 0.1)]))
    let preselected = result.preselectedForDeletion()
    #expect(preselected == ["ticket", "order", "qr"])
    for id in preselected {
      #expect(result.verdicts[id]?.suggestion == .delete)
    }
    #expect(result.ids(in: .transferReceipt) == ["receipt"])
    #expect(result.verdicts.count == features.count)
  }

  @Test("ids(in:) preserves input order")
  func idsInputOrder() {
    let result = analyze([
      TestSupport.features("q2", createdAt: at(10), qr: 0.5),
      TestSupport.features("x", createdAt: at(20)),
      TestSupport.features("q1", createdAt: at(0), qr: 0.5),
    ])
    #expect(result.ids(in: .qrCode) == ["q2", "q1"])
    #expect(result.ids(in: .other) == ["x"])
    #expect(result.ids(in: .expiredOrder).isEmpty)
  }

  @Test("reclaimableBytes sums known sizes and ignores unknown ids")
  func reclaimableBytes() {
    let result = AnalysisResult(verdicts: [:], clusters: [])
    let sizes: [String: Int64] = ["a": 1_000, "b": 2_500, "c": 7]
    #expect(result.reclaimableBytes(["a", "b", "missing"], sizes: sizes) == 3_500)
    #expect(result.reclaimableBytes([], sizes: sizes) == 0)
  }

  @Test("empty library")
  func emptyLibrary() {
    let result = analyze([])
    #expect(result.verdicts.isEmpty)
    #expect(result.clusters.isEmpty)
    #expect(result.preselectedForDeletion().isEmpty)
  }
}
