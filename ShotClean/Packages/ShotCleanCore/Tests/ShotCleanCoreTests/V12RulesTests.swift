import Foundation
import Testing

@testable import ShotCleanCore

/// v1.2 rules: protected assets, old screenshots, bursts, low-quality and utility photos.
@Suite("v1.2 rules")
struct V12RulesTests {
  let analyzer = LibraryAnalyzer(thresholds: TestSupport.thresholds)
  let classifier = ScreenshotClassifier(thresholds: TestSupport.thresholds)
  let now = TestSupport.now
  /// One day before `now`: too recent for any age rule.
  let base = TestSupport.date(2026, 10, 14, 9)

  func at(seconds: Double) -> Date { base.addingTimeInterval(seconds) }

  func analyze(_ features: [ScreenshotFeatures], distance: DistanceTable = DistanceTable([]))
    -> AnalysisResult
  {
    analyzer.analyze(features, distance: distance.callAsFunction, now: now)
  }

  // MARK: Protected

  @Test(
    "favorites, album members and edited assets are kept",
    arguments: [
      MetadataFlags(isFavorite: true, isScreenshot: true),
      MetadataFlags(isScreenshot: true, inUserAlbum: true),
      MetadataFlags(hasAdjustments: true, isScreenshot: true),
      MetadataFlags(isFavorite: true),
    ])
  func protectedKept(metadata: MetadataFlags) {
    // Old QR screenshot: would be deleted without protection.
    let verdict = classifier.classify(
      TestSupport.features("p", createdAt: TestSupport.daysAgo(60), qr: 0.6, metadata: metadata),
      now: now)
    #expect(verdict.suggestion == .keep)
    #expect(verdict.category == .other)
    #expect(!verdict.reason.isEmpty)
  }

  @Test("a protected receipt stays a receipt")
  func protectedReceipt() {
    let verdict = classifier.classify(
      TestSupport.features(
        "r", text: OCRSample.vietcombankTransfer,
        metadata: MetadataFlags(isFavorite: true, isScreenshot: true)),
      now: now)
    #expect(verdict.category == .transferReceipt)
    #expect(verdict.suggestion == .keep)
  }

  @Test("exact cluster prefers a protected member as keeper; protected copies are never deleted")
  func protectedExactKeeper() {
    let result = analyze([
      TestSupport.features("a", createdAt: at(seconds: 0), sha: "h", metadata: TestSupport.photo),
      TestSupport.features(
        "b", createdAt: at(seconds: 60), sha: "h", metadata: MetadataFlags(inUserAlbum: true)),
    ])
    #expect(result.clusters.first?.keeperID == "b")
    #expect(result.verdicts["a"]?.category == .exactDuplicate)
    #expect(result.verdicts["b"]?.suggestion == .keep)
    #expect(result.preselectedForDeletion() == ["a"])
  }

  @Test("near cluster prefers a protected member over a larger one")
  func protectedNearKeeper() {
    let result = analyze(
      [
        TestSupport.features("big", createdAt: at(seconds: 0), width: 1290, height: 2796),
        TestSupport.features(
          "fav", createdAt: at(seconds: 60), metadata: MetadataFlags(isFavorite: true)),
      ],
      distance: DistanceTable([("big", "fav", 0.1)]))
    #expect(result.clusters.first?.keeperID == "fav")
    #expect(result.verdicts["fav"]?.suggestion == .keep)
    #expect(result.verdicts["big"]?.category == .nearDuplicate)
  }

  // MARK: Old screenshots

  @Test("an old screenshot without other signals is deleted")
  func oldScreenshotDeleted() {
    let verdict = classifier.classify(
      TestSupport.features(
        "o", createdAt: TestSupport.daysAgo(45), text: "Hôm nay trời đẹp quá",
        metadata: TestSupport.screenshot),
      now: now)
    #expect(verdict.category == .oldScreenshot)
    #expect(verdict.suggestion == .delete)
  }

  @Test("age boundary, camera photos and undated screenshots")
  func oldScreenshotBoundaries() {
    let young = classifier.classify(
      TestSupport.features(
        "y", createdAt: TestSupport.daysAgo(29), metadata: TestSupport.screenshot),
      now: now)
    #expect(young == .other)
    let exactly = classifier.classify(
      TestSupport.features(
        "e", createdAt: TestSupport.daysAgo(30), metadata: TestSupport.screenshot),
      now: now)
    #expect(exactly.category == .oldScreenshot)
    let photo = classifier.classify(
      TestSupport.features("c", createdAt: TestSupport.daysAgo(90), metadata: TestSupport.photo),
      now: now)
    #expect(photo == .other)
    let undated = classifier.classify(
      TestSupport.features("u", createdAt: .distantPast, metadata: TestSupport.screenshot),
      now: now)
    #expect(undated == .other)
    let custom = ScreenshotClassifier(
      thresholds: Thresholds(oldScreenshotMinAgeDays: 60, calendar: TestSupport.calendar))
    #expect(
      custom.classify(
        TestSupport.features(
          "e", createdAt: TestSupport.daysAgo(45), metadata: TestSupport.screenshot),
        now: now) == .other)
  }

  @Test("a still-valid ticket captured long ago is not an old screenshot")
  func oldScreenshotSkipsValidTicket() {
    let verdict = classifier.classify(
      TestSupport.features(
        "t", createdAt: TestSupport.daysAgo(60),
        text: OCRSample.vietnamAirlinesFutureBoardingPass, metadata: TestSupport.screenshot),
      now: now)
    #expect(verdict == .other)
  }

  @Test(
    "an old screenshot with important-looking text goes to review",
    arguments: [
      "STK 0123456789 Nguyen Van A",
      "Số tài khoản: 1903 4567 8901",
      "Giao tới 12 đường Lê Lợi, phường Bến Nghé, quận 1",
      "Địa chỉ: 45 ngõ 12 Láng Hạ",
      "Gọi cho em nhé 0912 345 678",
      "Liên hệ +84 912.345.678",
      "Wifi nhà: mật khẩu là abc12345",
      "Password: hunter2",
    ])
  func oldScreenshotImportantText(text: String) {
    let verdict = classifier.classify(
      TestSupport.features(
        "i", createdAt: TestSupport.daysAgo(60), text: text, metadata: TestSupport.screenshot),
      now: now)
    #expect(verdict.category == .oldScreenshot)
    #expect(verdict.suggestion == .review)
  }

  @Test(
    "ordinary text does not look important",
    arguments: [
      "Giá 1.250.000đ, giảm 20%",
      "Quán cà phê mới mở, ngon lắm",
      "Mã giảm giá 12345678",
    ])
  func ordinaryTextNotImportant(text: String) {
    let verdict = classifier.classify(
      TestSupport.features(
        "n", createdAt: TestSupport.daysAgo(60), text: text, metadata: TestSupport.screenshot),
      now: now)
    #expect(verdict.category == .oldScreenshot)
    #expect(verdict.suggestion == .delete)
  }

  // MARK: Bursts

  @Test("burst keeps the newest shot; the gap boundary is inclusive")
  func burstKeeperNewest() {
    let result = analyze([
      TestSupport.features("c", createdAt: at(seconds: 13), metadata: TestSupport.screenshot),
      TestSupport.features("a", createdAt: at(seconds: 0), metadata: TestSupport.screenshot),
      TestSupport.features("b", createdAt: at(seconds: 5), metadata: TestSupport.screenshot),
      // 9 s after "c": starts a new run of one.
      TestSupport.features("d", createdAt: at(seconds: 22), metadata: TestSupport.screenshot),
    ], distance: DistanceTable([("a", "b", 0.1), ("b", "c", 0.1)]))
    #expect(result.clusters == [Cluster(kind: .burst, memberIDs: ["a", "b", "c"], keeperID: "c")])
    #expect(result.verdicts["a"]?.category == .burstShot)
    #expect(result.verdicts["a"]?.suggestion == .delete)
    #expect(result.verdicts["b"]?.category == .burstShot)
    #expect(result.verdicts["c"] == .other)
    #expect(result.verdicts["d"] == .other)
    #expect(result.preselectedForDeletion() == ["a", "b"])
  }

  @Test("bursts need screenshots with known dates")
  func burstOnlyScreenshots() {
    let photos = analyze([
      TestSupport.features("a", createdAt: at(seconds: 0), metadata: TestSupport.photo),
      TestSupport.features("b", createdAt: at(seconds: 2), metadata: TestSupport.photo),
    ])
    #expect(photos.clusters.isEmpty)
    let undated = analyze([
      TestSupport.features("a", createdAt: .distantPast, metadata: TestSupport.screenshot),
      TestSupport.features("b", createdAt: .distantPast, metadata: TestSupport.screenshot),
    ])
    #expect(undated.clusters.isEmpty)
  }

  @Test("exact-cluster members never join a burst")
  func burstExcludesExactMembers() {
    let result = analyze([
      TestSupport.features("a", createdAt: at(seconds: 0), metadata: TestSupport.screenshot),
      TestSupport.features(
        "b", createdAt: at(seconds: 4), sha: "h", metadata: TestSupport.screenshot),
      TestSupport.features(
        "c", createdAt: at(seconds: 6), sha: "h", metadata: TestSupport.screenshot),
      TestSupport.features("d", createdAt: at(seconds: 10), metadata: TestSupport.screenshot),
    ])
    #expect(result.clusters == [Cluster(kind: .exact, memberIDs: ["b", "c"], keeperID: "b")])
    #expect(result.verdicts["c"]?.category == .exactDuplicate)
    #expect(result.verdicts["a"] == .other)
    #expect(result.verdicts["d"] == .other)
  }

  @Test("QR beats burst; burst beats near duplicate; burst non-keepers skip near clustering")
  func burstPriority() {
    let result = analyze(
      [
        TestSupport.features(
          "q", createdAt: TestSupport.daysAgo(10), qr: 0.5, metadata: TestSupport.screenshot),
        TestSupport.features(
          "q2", createdAt: TestSupport.daysAgo(10).addingTimeInterval(3),
          metadata: TestSupport.screenshot),
        TestSupport.features("a", createdAt: at(seconds: 0), metadata: TestSupport.screenshot),
        TestSupport.features("b", createdAt: at(seconds: 3), metadata: TestSupport.screenshot),
      ],
      distance: DistanceTable([("a", "b", 0.1), ("q", "q2", 0.1)]))
    #expect(result.verdicts["q"]?.category == .qrCode)
    #expect(result.verdicts["a"]?.category == .burstShot)
    #expect(!result.clusters.contains { $0.kind == .near })
  }

  @Test("different screens taken seconds apart are not a burst")
  func burstNeedsSameContent() {
    let pageA = (1...20).map { "alpha\($0)" }.joined(separator: " ")
    let pageB = (1...20).map { "beta\($0)" }.joined(separator: " ")
    let byText = analyze([
      TestSupport.features(
        "a", createdAt: at(seconds: 0), text: pageA, metadata: TestSupport.screenshot),
      TestSupport.features(
        "b", createdAt: at(seconds: 2), text: pageB, metadata: TestSupport.screenshot),
    ], distance: DistanceTable([("a", "b", 0.1)]))
    #expect(byText.clusters.isEmpty)
    let byPicture = analyze(
      [
        TestSupport.features("a", createdAt: at(seconds: 0), metadata: TestSupport.screenshot),
        TestSupport.features("b", createdAt: at(seconds: 2), metadata: TestSupport.screenshot),
      ],
      distance: DistanceTable([("a", "b", 0.9)]))
    #expect(byPicture.clusters.isEmpty)
  }

  // MARK: Camera photos

  @Test("pixel statistics never flag a photo Vision rates acceptable; undated photos are kept")
  func lowQualityVetoes() {
    let rated = classifier.classify(
      TestSupport.features(
        "n", metadata: TestSupport.photo, luma: 0.01, sharpness: 1, aesthetics: 0.2),
      now: now)
    #expect(rated == .other)
    let undated = classifier.classify(
      TestSupport.features(
        "u", createdAt: .distantPast, metadata: TestSupport.photo, luma: 0.01),
      now: now)
    #expect(undated == .other)
  }

  @Test(
    "dark, blown-out, blurry or very low scored camera photos are deleted",
    arguments: [
      (0.02, 500.0, nil), (0.99, 500.0, nil), (0.5, 5.0, nil), (0.5, 500.0, -0.8),
    ] as [(Double, Double, Double?)])
  func lowQualityPhotos(luma: Double, sharpness: Double, aesthetics: Double?) {
    let verdict = classifier.classify(
      TestSupport.features(
        "l", metadata: TestSupport.photo, luma: luma, sharpness: sharpness,
        aesthetics: aesthetics),
      now: now)
    #expect(verdict.category == .lowQualityPhoto)
    #expect(verdict.suggestion == .delete)
  }

  @Test("good photos, unmeasured photos and screenshots are not low quality")
  func notLowQuality() {
    let good = classifier.classify(
      TestSupport.features(
        "g", metadata: TestSupport.photo, luma: 0.5, sharpness: 500, aesthetics: 0.3),
      now: now)
    #expect(good == .other)
    let unmeasured = classifier.classify(
      TestSupport.features("u", metadata: TestSupport.photo), now: now)
    #expect(unmeasured == .other)
    let screenshot = classifier.classify(
      TestSupport.features("s", metadata: TestSupport.screenshot, luma: 0.01, sharpness: 0),
      now: now)
    #expect(screenshot == .other)
    let favorite = classifier.classify(
      TestSupport.features("f", metadata: MetadataFlags(isFavorite: true), luma: 0.01),
      now: now)
    #expect(favorite.suggestion == .keep)
  }

  @Test("old utility photos go to review, recent ones are left alone")
  func utilityPhotos() {
    let old = classifier.classify(
      TestSupport.features(
        "u", createdAt: TestSupport.daysAgo(40), metadata: TestSupport.photo, luma: 0.6,
        sharpness: 400, isUtility: true),
      now: now)
    #expect(old.category == .utilityPhoto)
    #expect(old.suggestion == .review)
    let recent = classifier.classify(
      TestSupport.features(
        "r", createdAt: TestSupport.daysAgo(10), metadata: TestSupport.photo, isUtility: true),
      now: now)
    #expect(recent == .other)
    let result = analyze([
      TestSupport.features(
        "u", createdAt: TestSupport.daysAgo(40), metadata: TestSupport.photo, isUtility: true)
    ])
    #expect(result.preselectedForDeletion().isEmpty)
  }

  // MARK: Invariants

  @Test("receipts and protected assets are never .delete, whatever cluster they are in")
  func neverDeleteReceiptsOrProtected() {
    let fav = MetadataFlags(isFavorite: true, isScreenshot: true)
    let features = [
      // Burst: receipt and favorite as non-keepers.
      TestSupport.features(
        "r", createdAt: at(seconds: 0), text: OCRSample.mbBankTransfer,
        metadata: TestSupport.screenshot),
      TestSupport.features("f", createdAt: at(seconds: 2), metadata: fav),
      TestSupport.features("k", createdAt: at(seconds: 4), metadata: TestSupport.screenshot),
      // Exact duplicates of an old receipt and an old protected screenshot.
      TestSupport.features(
        "r1", createdAt: TestSupport.daysAgo(90), text: OCRSample.techcombankTransfer, sha: "r",
        metadata: TestSupport.screenshot),
      TestSupport.features(
        "r2", createdAt: TestSupport.daysAgo(89), text: OCRSample.techcombankTransfer, sha: "r",
        metadata: TestSupport.screenshot),
      TestSupport.features(
        "p1", createdAt: TestSupport.daysAgo(80), sha: "p", metadata: TestSupport.screenshot),
      TestSupport.features(
        "p2", createdAt: TestSupport.daysAgo(79), sha: "p",
        metadata: MetadataFlags(hasAdjustments: true, isScreenshot: true)),
      // Old, dark, protected photo.
      TestSupport.features(
        "d", createdAt: TestSupport.daysAgo(70), metadata: MetadataFlags(inUserAlbum: true),
        luma: 0.01),
    ]
    let result = analyze(features, distance: DistanceTable([("r", "f", 0.1), ("f", "k", 0.1)]))
    #expect(result.clusters.contains { $0.kind == .burst && $0.memberIDs == ["r", "f", "k"] })
    for id in ["r", "f", "r1", "r2", "p2", "d"] {
      #expect(result.verdicts[id]?.suggestion == .keep, "\(id)")
      #expect(!result.preselectedForDeletion().contains(id), "\(id)")
    }
    #expect(result.verdicts["p1"]?.category == .exactDuplicate)
  }

  @Test("metadata decodes tolerantly")
  func tolerantDecoding() throws {
    let flags = try JSONDecoder().decode(
      MetadataFlags.self, from: Data(#"{"isFavorite":true}"#.utf8))
    #expect(flags == MetadataFlags(isFavorite: true))
    let original = TestSupport.features("x", text: "abc")
    let encoded = try JSONEncoder().encode(original)
    let object = try JSONSerialization.jsonObject(with: encoded)
    guard var json = object as? [String: Any] else {
      Issue.record("features did not encode to a JSON object")
      return
    }
    for key in ["metadata", "meanLuma", "sharpness", "aestheticsScore", "isUtility"] {
      json[key] = nil
    }
    let decoded = try JSONDecoder().decode(
      ScreenshotFeatures.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded == original)
  }
}
