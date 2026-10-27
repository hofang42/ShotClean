import SwiftUI

/// Grid cell (S5): thumbnail, one-line reason badge and a selection ring.
/// Tapping anywhere on the cell toggles selection (the whole cell is the tap target); the
/// detail opens from the context menu (long press) or the VoiceOver action.
struct ThumbnailCell: View {
  let id: String
  let reason: String
  /// Full sentence read by VoiceOver (category, reason, date).
  let accessibilityText: String
  let isSelected: Bool
  let onToggle: () -> Void
  let onOpen: () -> Void

  var body: some View {
    Button(action: onToggle) {
      Color.clear
        .aspectRatio(Theme.thumbnailAspectRatio, contentMode: .fit)
        .overlay { ThumbnailImage(id: id) }
        .overlay {
          if isSelected {
            Theme.accent.opacity(0.18)
          }
        }
        .overlay(alignment: .bottom) { reasonBadge }
        .clipShape(.rect(cornerRadius: Theme.Radius.thumbnail))
        .overlay {
          RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
            .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 4)
        }
        .overlay(alignment: .topTrailing) {
          SelectionRing(isSelected: isSelected)
        }
        .contentShape(.rect(cornerRadius: Theme.Radius.thumbnail))
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button(Strings.Grid.showDetail, systemImage: "info.circle", action: onOpen)
      Button(
        isSelected ? Strings.Detail.deselect : Strings.Detail.select,
        systemImage: isSelected ? "xmark.circle" : "checkmark.circle",
        action: onToggle)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityValue(isSelected ? Strings.Grid.selected : Strings.Grid.notSelected)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction { onToggle() }
    .accessibilityAction(named: Strings.Grid.showDetail) { onOpen() }
  }

  @ViewBuilder private var reasonBadge: some View {
    if !reason.isEmpty {
      Text(reason)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.6), in: .rect(cornerRadius: 5))
        .padding(Theme.Spacing.xs)
    }
  }
}
