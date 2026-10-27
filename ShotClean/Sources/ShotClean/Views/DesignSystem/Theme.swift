import SwiftUI
import UIKit

/// Design tokens from UI-SPEC §3.
enum Theme {
  static let accent = Color(light: 0x4338CA, dark: 0x8B8FFF)
  /// Brand gradient endpoints (indigo to mint), matching the app icon.
  static let brandStart = Color(light: 0x3B2BB8, dark: 0x4A3FE0)
  static let brandEnd = Color(light: 0x0FB5A0, dark: 0x14C9B0)
  /// Computed: avoids a global stored `LinearGradient` under Swift 6 strict concurrency.
  static var brandGradient: LinearGradient {
    LinearGradient(
      colors: [brandStart, brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
  /// Soft shadow color for cards.
  static let shadow = Color.black.opacity(0.08)
  static let keep = Color(light: 0x14925A, dark: 0x3DD68C)
  static let destructive = Color.red
  /// Solid backgrounds for content (no glass on content cards).
  static let background = Color(uiColor: .systemGroupedBackground)
  static let card = Color(uiColor: .secondarySystemGroupedBackground)
  static let placeholder = Color(uiColor: .tertiarySystemFill)

  enum Radius {
    static let card: CGFloat = 20
    static let hero: CGFloat = 28
    static let thumbnail: CGFloat = 10
    static let button: CGFloat = 14
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
