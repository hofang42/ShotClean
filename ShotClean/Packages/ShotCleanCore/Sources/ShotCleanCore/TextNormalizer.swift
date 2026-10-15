import Foundation

/// Normalizes OCR text before any keyword matching.
public enum TextNormalizer {
  /// Lowercases, strips diacritics (Vietnamese tones and marks), maps `đ`/`Đ` to `d`,
  /// and collapses every run of whitespace/newlines into a single space.
  ///
  /// `đ` is mapped explicitly because it is a distinct letter, not `d` plus a combining mark,
  /// so diacritic folding leaves it untouched. A fixed POSIX locale keeps behavior identical
  /// on Apple platforms and Linux.
  public static func fold(_ s: String) -> String {
    let folded =
      s
      .replacingOccurrences(of: "đ", with: "d")
      .replacingOccurrences(of: "Đ", with: "d")
      .folding(
        options: [.diacriticInsensitive, .caseInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .lowercased()
    return
      folded
      .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
      .joined(separator: " ")
  }
}
