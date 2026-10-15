import Foundation

/// Finds calendar dates in OCR text.
///
/// Supported (after `TextNormalizer.fold`):
/// - `dd/MM/yyyy`, `dd-MM-yyyy`, `dd.MM.yyyy`, `dd/MM/yy` (same separator twice)
/// - `yyyy-MM-dd` (ISO)
/// - `12 thg 9, 2026`, `12 tháng 9 2026`, `ngày 12 tháng 9 năm 2026`, `12 thg 9`
/// - `dd/MM` (slash only, at least one two-digit part, so `1/2` page counters are ignored)
///
/// Dates without a year take the reference year, or the previous year when that would put
/// them more than 60 days after `reference`. Invalid dates (`32/13`, `31/02`) are dropped.
/// Amounts (`1.250.000`), times (`10:15`) and long digit runs are rejected by requiring that a
/// match is not glued to other digits or digit separators.
///
/// Returned dates are start-of-day in `calendar`'s time zone, distinct and sorted ascending.
public enum DateExtractor {
  /// Maximum number of days a year-less date may lie after the reference date.
  static let yearInferenceWindowDays = 60

  private static let notAfterNumber = #"(?<![\d.,/:-])"#
  private static let notBeforeNumber = #"(?![\d]|[.,/:-]\d)"#

  public static func dates(in text: String, reference: Date, calendar: Calendar) -> [Date] {
    let folded = TextNormalizer.fold(text)
    var found = Set<Date>()

    func add(day: Int, month: Int, year: Int?) {
      if let date = makeDate(
        day: day, month: month, year: year, reference: reference, calendar: calendar)
      {
        found.insert(date)
      }
    }

    // dd/MM/yyyy, dd-MM-yyyy, dd.MM.yyyy, dd/MM/yy
    for groups in matches(
      notAfterNumber + #"(\d{1,2})([/.-])(\d{1,2})\2(\d{4}|\d{2})"# + notBeforeNumber, in: folded)
    {
      guard let day = Int(groups[1]), let month = Int(groups[3]), let rawYear = Int(groups[4])
      else { continue }
      add(day: day, month: month, year: groups[4].count == 2 ? 2000 + rawYear : rawYear)
    }

    // yyyy-MM-dd
    for groups in matches(
      notAfterNumber + #"(\d{4})-(\d{1,2})-(\d{1,2})"# + notBeforeNumber, in: folded)
    {
      guard let year = Int(groups[1]), let month = Int(groups[2]), let day = Int(groups[3]) else {
        continue
      }
      add(day: day, month: month, year: year)
    }

    // 12 thg 9, 2026 · 12 thang 9 nam 2026 · 12 thg 9
    let vietnamese =
      #"(?<!\d)(\d{1,2})\s*(?:thg|thang)\s*(\d{1,2})(?:\s*,?\s*(?:nam\s*)?(\d{4}))?(?!\d)"#
    for groups in matches(vietnamese, in: folded) {
      guard let day = Int(groups[1]), let month = Int(groups[2]) else { continue }
      add(day: day, month: month, year: Int(groups[3]))
    }

    // dd/MM (year inferred)
    for groups in matches(notAfterNumber + #"(\d{1,2})/(\d{1,2})"# + notBeforeNumber, in: folded) {
      guard groups[1].count == 2 || groups[2].count == 2 else { continue }
      guard let day = Int(groups[1]), let month = Int(groups[2]) else { continue }
      add(day: day, month: month, year: nil)
    }

    return found.sorted()
  }

  /// Builds a validated start-of-day date; `nil` for impossible dates or out-of-range years.
  private static func makeDate(
    day: Int, month: Int, year: Int?, reference: Date, calendar: Calendar
  ) -> Date? {
    guard (1...12).contains(month), (1...31).contains(day) else { return nil }
    guard let year else {
      let referenceYear = calendar.component(.year, from: reference)
      guard
        let candidate = validDate(day: day, month: month, year: referenceYear, calendar: calendar)
      else {
        // e.g. 29/02 in a non-leap reference year: try the previous year.
        return validDate(day: day, month: month, year: referenceYear - 1, calendar: calendar)
      }
      let limit =
        calendar.date(byAdding: .day, value: yearInferenceWindowDays, to: reference) ?? reference
      if candidate > limit {
        return validDate(day: day, month: month, year: referenceYear - 1, calendar: calendar)
      }
      return candidate
    }
    guard (2000...2100).contains(year) else { return nil }
    return validDate(day: day, month: month, year: year, calendar: calendar)
  }

  private static func validDate(day: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
    let components = DateComponents(year: year, month: month, day: day)
    guard let date = calendar.date(from: components) else { return nil }
    let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
    guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
    return date
  }

  /// All matches of `pattern` in `text`, each as its capture groups (index 0 = whole match,
  /// empty string for groups that did not participate).
  private static func matches(_ pattern: String, in text: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      assertionFailure("invalid date pattern \(pattern)")
      return []
    }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).map { match in
      (0..<match.numberOfRanges).map { index in
        Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
      }
    }
  }
}
