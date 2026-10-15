import Foundation

/// Locale-independent date formatting for user-facing reasons, in the calendar's time zone.
extension Calendar {
  /// `dd/MM/yyyy`
  func dayMonthYear(_ date: Date) -> String {
    let parts = dateComponents([.year, .month, .day], from: date)
    return "\(twoDigits(parts.day))/\(twoDigits(parts.month))/\(parts.year ?? 0)"
  }

  /// `dd/MM`
  func dayMonth(_ date: Date) -> String {
    let parts = dateComponents([.month, .day], from: date)
    return "\(twoDigits(parts.day))/\(twoDigits(parts.month))"
  }

  /// Whole days elapsed from `start` to `end` (negative if `end` is earlier).
  func wholeDays(from start: Date, to end: Date) -> Int {
    dateComponents([.day], from: start, to: end).day ?? 0
  }

  private func twoDigits(_ value: Int?) -> String {
    let value = value ?? 0
    return value < 10 ? "0\(value)" : "\(value)"
  }
}
