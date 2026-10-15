import Foundation

/// Number, byte and date formatting in `vi_VN` (UI-SPEC §6: `1.240`, `1,2 GB`, `12/09/2026`).
enum Format {
  static let locale = Locale(identifier: "vi_VN")

  static func count(_ value: Int) -> String {
    value.formatted(.number.locale(locale))
  }

  static func bytes(_ value: Int64) -> String {
    value.formatted(.byteCount(style: .file, spellsOutZero: false).locale(locale))
  }

  /// `12/09/2026`
  static func date(_ date: Date) -> String {
    date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(locale))
  }

  /// Spelled-out date for VoiceOver, e.g. "12 tháng 9, 2026".
  static func spokenDate(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.wide).year().locale(locale))
  }

  static func decimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
  }
}
