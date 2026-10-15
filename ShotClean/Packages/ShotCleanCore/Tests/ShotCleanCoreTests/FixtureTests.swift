import Foundation
import Testing

@testable import ShotCleanCore

/// One row of `Fixtures/manifest.json`.
struct FixtureEntry: Decodable, Sendable, CustomTestStringConvertible {
  let file: String
  let createdAt: String
  let qrAreaRatio: Double
  let expectedCategory: String
  let expectedSuggestion: String
  let note: String
  /// Bug id from `tasks/bugs.md` when the classifier is known to disagree with the label.
  let knownIssue: String?

  var testDescription: String { file }
}

/// Loads the file-based OCR fixtures bundled with the test target.
enum Fixtures {
  /// Fixed clock for the whole fixture set: 15/10/2026 09:00 (UTC+7).
  static let now: Date = parseDate("2026-10-15T09:00:00+07:00")

  static let entries: [FixtureEntry] = {
    guard
      let url = Bundle.module.url(
        forResource: "manifest", withExtension: "json", subdirectory: "Fixtures")
    else { preconditionFailure("Fixtures/manifest.json missing from test bundle") }
    do {
      return try JSONDecoder().decode([FixtureEntry].self, from: Data(contentsOf: url))
    } catch {
      preconditionFailure("cannot decode manifest.json: \(error)")
    }
  }()

  static func text(_ file: String) throws -> String {
    let name = (file as NSString).deletingPathExtension
    let ext = (file as NSString).pathExtension
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
      "fixture \(file) missing")
    return try String(contentsOf: url, encoding: .utf8)
  }

  static func parseDate(_ iso: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: iso) else {
      preconditionFailure("bad ISO8601 date \(iso)")
    }
    return date
  }

  static func features(_ entry: FixtureEntry) throws -> ScreenshotFeatures {
    ScreenshotFeatures(
      id: entry.file,
      createdAt: parseDate(entry.createdAt),
      pixelSize: PixelSize(width: 1179, height: 2556),
      text: try text(entry.file),
      qrAreaRatio: entry.qrAreaRatio
    )
  }

  static func classify(_ entry: FixtureEntry) throws -> Verdict {
    ScreenshotClassifier(thresholds: TestSupport.thresholds)
      .classify(try features(entry), now: now)
  }
}

@Suite("Fixtures (file-based OCR samples)")
struct FixtureTests {
  @Test("manifest is well-formed and covers at least 30 fixtures")
  func manifestShape() throws {
    let entries = Fixtures.entries
    #expect(entries.count >= 30)
    #expect(Set(entries.map(\.file)).count == entries.count, "duplicate file names")
    for entry in entries {
      #expect(ShotCleanCore.Category(rawValue: entry.expectedCategory) != nil, "\(entry.file)")
      #expect(Verdict.Suggestion(rawValue: entry.expectedSuggestion) != nil, "\(entry.file)")
      #expect((0...1).contains(entry.qrAreaRatio), "\(entry.file)")
      #expect(!(try Fixtures.text(entry.file)).isEmpty, "\(entry.file)")
    }
  }

  @Test(
    "classifier verdict matches the labelled category and suggestion", arguments: Fixtures.entries)
  func fixtureVerdict(entry: FixtureEntry) throws {
    let verdict = try Fixtures.classify(entry)
    let check = {
      #expect(
        verdict.category.rawValue == entry.expectedCategory,
        "\(entry.file): \(entry.note) — reason: \(verdict.reason)")
      #expect(verdict.suggestion.rawValue == entry.expectedSuggestion, "\(entry.file)")
    }
    if let bug = entry.knownIssue {
      withKnownIssue("\(bug) (see tasks/bugs.md)") { check() }
    } else {
      check()
    }
    // Every delete suggestion must carry a reason (SPEC Boundaries).
    if verdict.suggestion == .delete { #expect(!verdict.reason.isEmpty) }
  }

  private struct Outcome {
    let entry: FixtureEntry
    let verdict: Verdict
  }

  private func outcomes(_ entries: [FixtureEntry]) throws -> [Outcome] {
    try entries.map { Outcome(entry: $0, verdict: try Fixtures.classify($0)) }
  }

  /// Precision of `.delete`: correct deletes / all delete suggestions (`nil` when none).
  private func deletePrecision(_ outcomes: [Outcome]) -> (precision: Double, hits: Int, total: Int)
  {
    let suggested = outcomes.filter { $0.verdict.suggestion == .delete }
    let hits = suggested.filter { $0.entry.expectedSuggestion == "delete" }.count
    return (suggested.isEmpty ? 1 : Double(hits) / Double(suggested.count), hits, suggested.count)
  }

  @Test("SPEC success criteria: zero receipts suggested for deletion")
  func noReceiptDeleted() throws {
    let all = try outcomes(Fixtures.entries)
    let receipts = all.filter {
      $0.entry.expectedCategory == ShotCleanCore.Category.transferReceipt.rawValue
    }
    #expect(receipts.count >= 10)
    for receipt in receipts {
      #expect(receipt.verdict.suggestion != .delete, "\(receipt.entry.file) suggested for delete")
    }
    // Same guarantee through the library-level API used by the app.
    let features = try Fixtures.entries.map(Fixtures.features)
    let result = LibraryAnalyzer(thresholds: TestSupport.thresholds)
      .analyze(features, distance: { _, _ in nil }, now: Fixtures.now)
    let preselected = result.preselectedForDeletion()
    for receipt in receipts {
      #expect(!preselected.contains(receipt.entry.file))
    }
  }

  @Test("SPEC success criteria: delete precision ≥ 0.95 on fixtures without a logged bug")
  func deletePrecisionClean() throws {
    let clean = try outcomes(Fixtures.entries.filter { $0.knownIssue == nil })
    let (precision, hits, total) = deletePrecision(clean)
    print("[fixtures] delete precision (no known bugs): \(hits)/\(total) = \(precision)")
    #expect(total > 0)
    #expect(precision >= 0.95)
  }

  @Test("SPEC success criteria: delete precision ≥ 0.95 on the full fixture set")
  func deletePrecisionAll() throws {
    let all = try outcomes(Fixtures.entries)
    let (precision, hits, total) = deletePrecision(all)
    let falsePositives = all.filter {
      $0.verdict.suggestion == .delete && $0.entry.expectedSuggestion != "delete"
    }.map(\.entry.file)
    print(
      "[fixtures] delete precision (all): \(hits)/\(total) = \(precision); false positives: \(falsePositives)"
    )
    #expect(total > 0)
    #expect(precision >= 0.95, "false positives: \(falsePositives)")
  }
}
