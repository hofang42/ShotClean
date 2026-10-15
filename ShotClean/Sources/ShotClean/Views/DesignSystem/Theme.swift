import SwiftUI
import UIKit

/// Design tokens from UI-SPEC §3.
enum Theme {
  static let accent = Color(light: 0x2F6BFF, dark: 0x5B8CFF)
  static let keep = Color(light: 0x1E9E62, dark: 0x34C77B)
  static let destructive = Color.red
  /// Solid backgrounds for content (no glass on content cards).
  static let background = Color(uiColor: .systemGroupedBackground)
  static let card = Color(uiColor: .secondarySystemGroupedBackground)
  static let placeholder = Color(uiColor: .tertiarySystemFill)

  enum Radius {
    static let card: CGFloat = 16
    static let thumbnail: CGFloat = 10
    static let button: CGFloat = 12
    static let floatingBar: CGFloat = 22
  }

  enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
  }

  /// Screenshot thumbnails are shown at a fixed 9:16 aspect ratio.
  static let thumbnailAspectRatio: CGFloat = 9.0 / 16.0
}

extension Color {
  /// A color that switches between two sRGB hex values for light and dark mode.
  init(light: UInt32, dark: UInt32) {
    self.init(
      uiColor: UIColor { traits in
        makeUIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
      })
  }
}

private func makeUIColor(hex: UInt32) -> UIColor {
  UIColor(
    red: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: 1
  )
}
