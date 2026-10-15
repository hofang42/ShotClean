import SwiftUI

/// Selection indicator in the top-right corner of a thumbnail. Uses a checkmark, not only
/// color, to show the selected state. Hidden from VoiceOver; the cell exposes the state.
struct SelectionRing: View {
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.title3.weight(.semibold))
        .symbolRenderingMode(.palette)
        .foregroundStyle(Color.white, isSelected ? Theme.accent : Color.black.opacity(0.25))
        .shadow(color: .black.opacity(0.3), radius: 1)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityHidden(true)
  }
}
