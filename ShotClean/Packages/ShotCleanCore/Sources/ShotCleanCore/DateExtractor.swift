import Foundation

/// Finds calendar dates in OCR text.
///
/// Supported (after `TextNormalizer.fold`):
/// - `dd/MM/yyyy`, `dd-MM-yyyy`, `dd.MM.yyyy`, `dd/MM/yy` (same separator twice)
/// - `yyyy-MM-dd` (ISO)
/// - `12 thg 9, 2026`, `12 tháng 9 2026`, `ngày 12 tháng 9 năm 2026`, `12 thg 9`
/// - `dd/MM` (slash only, at least one two-digit part, so `1/2` page counters are ignored)
///
/// Dates without a year take whichever of the previous, same or next year puts them closest to
/// `reference`, ignoring candidates more than 60 days after it: `02/01` read on 30/12 is next
/// January, `31/12` read on 02/01 is last December, `20/12` read on 15/10 is last December.
/// Invalid dates (`32/13`, `31/02`) are dropped.
/// Amounts (`1.250.000`), times (`10:15`) and long digit runs are rejected by requiring that a
/// match is not glued to other digits or digit separators.
///
/// Returned dates are start-of-day in `calendar`'s time zone, distinct and sorted ascending.
///
/// Implementation: a single left-to-right pass over the UTF-8 bytes (BUG-6). It is equivalent
/// to these regular expressions tried in this order at each position (ASCII digits only):
/// ```
/// (?<![\d.,/:-])(\d{1,2})([/.-])(\d{1,2})\2(\d{4}|\d{2})(?![\d]|[.,/:-]\d)
/// (?<![\d.,/:-])(\d{4})-(\d{1,2})-(\d{1,2})(?![\d]|[.,/:-]\d)
/// (?<!\d)(\d{1,2})\s*(?:thg|thang)\s*(\d{1,2})(?:\s*,?\s*(?:nam\s*)?(\d{4}))?(?!\d)
/// (?<![\d.,/:-])(\d{1,2})/(\d{1,2})(?![\d]|[.,/:-]\d)
/// ```
public enum DateExtractor {
  /// Maximum number of days a year-less date may lie after the reference date.
  static let yearInferenceWindowDays = 60

  public static func dates(in text: String, reference: Date, calendar: Calendar) -> [Date] {
    dates(inFolded: TextNormalizer.fold(text), reference: reference, calendar: calendar)
  }

  /// Same as `dates(in:reference:calendar:)` for text already passed through
  /// `TextNormalizer.fold`.
  static func dates(inFolded folded: String, reference: Date, calendar: Calendar) -> [Date] {
    var seen = Set<DayKey>()
    var found = Set<Date>()
    var scanner = Scanner(bytes: Array(folded.utf8))
    while let key = scanner.next() {
      // OCR text repeats the same date many times; build each distinct date once.
      guard seen.insert(key).inserted else { continue }
      if let date = makeDate(
        day: key.day, month: key.month, year: key.year, reference: reference, calendar: calendar)
      {
        found.insert(date)
      }
    }
    return found.sorted()
  }

  struct DayKey: Hashable {
    let day: Int
    let month: Int
    let year: Int?
  }

  /// Single-pass date tokenizer over folded UTF-8 bytes.
  private struct Scanner {
    let bytes: [UInt8]
    var index = 0

    /// A maximal run of ASCII digits; `value` holds at most its first 4 digits.
    private struct Run {
      let start: Int
      let end: Int
      let value: Int
      var length: Int { end - start }
    }

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func next() -> DayKey? {
      while index < bytes.count {
        guard Self.isDigit(bytes[index]) else {
          index += 1
          continue
        }
        // Every pattern needs a non-digit before its first digit, so only run starts count.
        guard let first = run(at: index) else { return nil }
        if let (key, end) = match(first) {
          index = end
          return key
        }
        index = first.end
      }
      return nil
    }

    private func match(_ first: Run) -> (DayKey, Int)? {
      let fenced = first.start == 0 || !Self.isFence(bytes[first.start - 1])
      if fenced, let result = dayMonthYear(first) { return result }
      if fenced, let result = iso(first) { return result }
      if let result = vietnamese(first) { return result }
      if fenced, let result = dayMonth(first) { return result }
      return nil
    }

    /// `dd/MM/yyyy`, `dd-MM-yyyy`, `dd.MM.yyyy`, `dd/MM/yy`.
    private func dayMonthYear(_ day: Run) -> (DayKey, Int)? {
      guard (1...2).contains(day.length), let separator = byte(day.end),
        separator == .slash || separator == .dash || separator == .dot,
        let month = run(at: day.end + 1), (1...2).contains(month.length),
        byte(month.end) == separator,
        let year = run(at: month.end + 1), year.length == 4 || year.length == 2,
        notBeforeNumber(year.end)
      else { return nil }
      let fullYear = year.length == 2 ? 2000 + year.value : year.value
      return (DayKey(day: day.value, month: month.value, year: fullYear), year.end)
    }

    /// `yyyy-MM-dd`.
    private func iso(_ year: Run) -> (DayKey, Int)? {
      guard year.length == 4, byte(year.end) == .dash,
        let month = run(at: year.end + 1), (1...2).contains(month.length),
        byte(month.end) == .dash,
        let day = run(at: month.end + 1), (1...2).contains(day.length),
        notBeforeNumber(day.end)
      else { return nil }
      return (DayKey(day: day.value, month: month.value, year: year.value), day.end)
    }

    /// `12 thg 9, 2026`, `12 thang 9 nam 2026`, `12 thg 9`.
    private func vietnamese(_ day: Run) -> (DayKey, Int)? {
      guard (1...2).contains(day.length) else { return nil }
      var cursor = skipSpaces(day.end)
      if hasPrefix("thg", at: cursor) {
        cursor += 3
      } else if hasPrefix("thang", at: cursor) {
        cursor += 5
      } else {
        return nil
      }
      cursor = skipSpaces(cursor)
      guard let month = run(at: cursor), (1...2).contains(month.length) else { return nil }
      // Optional year: \s*,?\s*(?:nam\s*)?(\d{4})(?!\d)
      var yearCursor = skipSpaces(month.end)
      if byte(yearCursor) == .comma { yearCursor += 1 }
      yearCursor = skipSpaces(yearCursor)
      if hasPrefix("nam", at: yearCursor) { yearCursor = skipSpaces(yearCursor + 3) }
      if let year = run(at: yearCursor), year.length == 4 {
        return (DayKey(day: day.value, month: month.value, year: year.value), year.end)
      }
      return (DayKey(day: day.value, month: month.value, year: nil), month.end)
    }

    /// `dd/MM`, at least one part with two digits.
    private func dayMonth(_ day: Run) -> (DayKey, Int)? {
      guard (1...2).contains(day.length), byte(day.end) == .slash,
        let month = run(at: day.end + 1), (1...2).contains(month.length),
        day.length == 2 || month.length == 2,
        notBeforeNumber(month.end)
      else { return nil }
      return (DayKey(day: day.value, month: month.value, year: nil), month.end)
    }

    // MARK: Helpers

    /// The maximal digit run starting at `start`, `nil` if `start` is not a digit.
    private func run(at start: Int) -> Run? {
      guard start < bytes.count, Self.isDigit(bytes[start]) else { return nil }
      var end = start
      var value = 0
      while end < bytes.count, Self.isDigit(bytes[end]) {
        if end - start < 4 { value = value * 10 + Int(bytes[end] - .zero) }
        end += 1
      }
      return Run(start: start, end: end, value: value)
    }

    /// `(?![\d]|[.,/:-]\d)` at `position`.
    private func notBeforeNumber(_ position: Int) -> Bool {
      guard let next = byte(position) else { return true }
      if Self.isDigit(next) { return false }
      if Self.isFence(next), let after = byte(position + 1), Self.isDigit(after) { return false }
      return true
    }

    private func skipSpaces(_ position: Int) -> Int {
      var cursor = position
      while let next = byte(cursor), Self.isSpace(next) { cursor += 1 }
      return cursor
    }

    private func hasPrefix(_ word: StaticString, at position: Int) -> Bool {
      word.withUTF8Buffer { buffer in
        position + buffer.count <= bytes.count
          && buffer.indices.allSatisfy { bytes[position + $0] == buffer[$0] }
      }
    }

    private func byte(_ position: Int) -> UInt8? {
      position < bytes.count ? bytes[position] : nil
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= .zero && byte <= .nine }

    /// Digits and the separators `. , / : -` that glue numbers together.
    private static func isFence(_ byte: UInt8) -> Bool {
      isDigit(byte) || byte == .dot || byte == .comma || byte == .slash || byte == .colon
        || byte == .dash
    }

    /// ASCII whitespace (folded text has its whitespace runs collapsed already).
    private static func isSpace(_ byte: UInt8) -> Bool {
      byte == 0x20 || (0x09...0x0D).contains(byte)
    }
  }

  /// Builds a validated start-of-day date; `nil` for impossible dates or out-of-range years.
  private static func makeDate(
    day: Int, month: Int, year: Int?, reference: Date, calendar: Calendar
  ) -> Date? {
    guard (1...12).contains(month), (1...31).contains(day) else { return nil }
    guard let year else {
      // BUG-5: consider last, this and next year; keep the candidate closest to `reference`
      // among those at most `yearInferenceWindowDays` after it.
      let referenceYear = calendar.component(.year, from: reference)
      let limit =
        calendar.date(byAdding: .day, value: yearInferenceWindowDays, to: reference) ?? reference
      return [referenceYear - 1, referenceYear, referenceYear + 1]
        .compactMap { validDate(day: day, month: month, year: $0, calendar: calendar) }
        .filter { $0 <= limit }
        .min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
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
}

extension UInt8 {
  fileprivate static let zero = UInt8(ascii: "0")
  fileprivate static let nine = UInt8(ascii: "9")
  fileprivate static let dot = UInt8(ascii: ".")
  fileprivate static let comma = UInt8(ascii: ",")
  fileprivate static let slash = UInt8(ascii: "/")
  fileprivate static let colon = UInt8(ascii: ":")
  fileprivate static let dash = UInt8(ascii: "-")
}
