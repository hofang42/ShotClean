import Foundation

/// Normalizes OCR text before any keyword matching.
public enum TextNormalizer {
  /// Lowercases, strips diacritics (Vietnamese tones and marks), maps `đ`/`Đ` to `d`,
  /// and collapses every run of whitespace/newlines into a single space.
  ///
  /// `đ` is mapped explicitly because it is a distinct letter, not `d` plus a combining mark,
  /// so diacritic folding leaves it untouched. A fixed POSIX locale keeps behavior identical
  /// on Apple platforms and Linux.
  ///
  /// The `đ` mapping and whitespace collapsing share one pass over the scalars (BUG-6).
  public static func fold(_ s: String) -> String {
    let folded =
      s
      .folding(
        options: [.diacriticInsensitive, .caseInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .lowercased()
    var result = String.UnicodeScalarView()
    var pendingSpace = false
    for scalar in folded.unicodeScalars {
      if scalar.properties.isWhitespace {
        pendingSpace = !result.isEmpty
        continue
      }
      if pendingSpace {
        result.append(" ")
        pendingSpace = false
      }
      // U+0110 Đ, U+0111 đ
      result.append(scalar.value == 0x110 || scalar.value == 0x111 ? "d" : scalar)
    }
    return String(result)
  }
}
