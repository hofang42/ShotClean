import SwiftUI

/// Floating bottom bar for primary actions. Use inside `.safeAreaInset(edge: .bottom)`.
/// Glass on iOS 26, material before. Buttons stack vertically at accessibility text sizes.
struct FloatingActionBar<Content: View>: View {
  @ViewBuilder let content: Content

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
      : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))

    layout {
      content
    }
    .controlSize(.large)
    .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
    .padding(Theme.Spacing.s + 2)
    .glassOrMaterial(cornerRadius: Theme.Radius.floatingBar)
    .padding(.horizontal, Theme.Spacing.l)
    .padding(.bottom, Theme.Spacing.s)
  }
}
