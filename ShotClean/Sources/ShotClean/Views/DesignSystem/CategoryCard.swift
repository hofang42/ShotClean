import SwiftUI

/// Overview row (S4): colored icon, title, one-line reason, count, size and chevron.
/// Wrap it in a `NavigationLink`. Switches to a vertical layout at accessibility text sizes.
struct CategoryCard: View {
  let category: ShotCategory
  let count: Int
  let bytes: Int64
  var badgeText: String?
  /// Protected cards (receipts) get a dashed keep-colored border.
  var isProtected = false
  var detail: String?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
      : AnyLayout(HStackLayout(spacing: Theme.Spacing.m))

    layout {
      icon
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: Theme.Spacing.s) {
          Text(category.title)
            .font(.headline)
            .foregroundStyle(.primary)
          if let badgeText {
            Text(badgeText)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(ShotCategory.expiredTicket.tint)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(ShotCategory.expiredTicket.tint.opacity(0.18), in: .capsule)
          }
        }
        Text(detail ?? category.summary)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
      }
      if !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: Theme.Spacing.s)
      }
      VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
        Text(Strings.Overview.photoCount(Format.count(count)))
          .font(.subheadline.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.primary)
        if bytes > 0 {
          Text(Format.bytes(bytes))
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
      if !dynamicTypeSize.isAccessibilitySize {
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
    }
    .padding(Theme.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
    .overlay {
      if isProtected {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
          .strokeBorder(
            Theme.keep.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
      }
    }
    .contentShape(.rect(cornerRadius: Theme.Radius.card))
    .accessibilityElement(children: .combine)
  }

  private var icon: some View {
    Image(systemName: category.symbolName)
      .font(.body.weight(.semibold))
      .foregroundStyle(.white)
      .frame(width: 36, height: 36)
      .background(category.tint, in: .rect(cornerRadius: 9))
      .accessibilityHidden(true)
  }
}
