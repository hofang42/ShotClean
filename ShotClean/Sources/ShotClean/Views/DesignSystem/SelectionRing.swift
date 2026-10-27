import SwiftUI

/// Selection indicator in the top-right corner of a thumbnail. Uses a checkmark, not only
/// color, to show the selected state. Purely visual: the whole thumbnail is the (≥ 44 pt) tap
/// target. Hidden from VoiceOver; the cell exposes the state.
struct SelectionRing: View {
  let isSelected: Bool

  var body: some View {
    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
      .font(.title2.weight(.semibold))
      .symbolRenderingMode(.palette)
      .foregroundStyle(Color.white, isSelected ? Theme.accent : Color.black.opacity(0.3))
      .shadow(color: .black.opacity(0.35), radius: 1.5)
      .contentTransition(.symbolEffect(.replace))
      .padding(Theme.Spacing.xs + 2)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}
