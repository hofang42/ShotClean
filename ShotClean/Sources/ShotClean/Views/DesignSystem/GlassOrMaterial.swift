import SwiftUI

extension View {
  /// Liquid Glass on iOS 26+, `.ultraThinMaterial` before. Only for floating controls,
  /// never for content cards, and never stacked on another glass surface (UI-SPEC §5).
  @ViewBuilder
  func glassOrMaterial(cornerRadius: CGFloat = 20) -> some View {
    if #available(iOS 26, *) {
      glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    } else {
      background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
    }
  }
}
