import ShotCleanCore
import SwiftUI

/// One duplicate cluster (S6) as a horizontal row. The keeper has a keep-colored border and a
/// "Giữ" tag that moves with `matchedGeometryEffect`. Tap another photo to make it the keeper;
/// the ring toggles deletion for that photo.
struct ClusterRow: View {
  struct Member: Identifiable {
    let id: String
    let dateText: String
    let spokenDate: String
    let isReceipt: Bool
    let isSelected: Bool
  }

  let kind: Cluster.Kind
  let members: [Member]
  let keeperID: String
  /// "Cũ nhất" / "Nét nhất" / "Bạn chọn".
  let keeperNote: String
  let onSetKeeper: (String) -> Void
  let onToggle: (String) -> Void
  let onSelectOthers: () -> Void
  let onCompare: () -> Void

  @Namespace private var keeperNamespace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var cellWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 140 : 100 }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      header
      ScrollView(.horizontal) {
        HStack(spacing: Theme.Spacing.s) {
          ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
            memberCell(member, index: index)
          }
        }
        .padding(.vertical, 2)
      }
      .scrollIndicators(.hidden)
      actions
    }
    .padding(Theme.Spacing.m)
    .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
    .animation(reduceMotion ? nil : .snappy, value: keeperID)
  }

  private var header: some View {
    let title = kind == .exact ? Strings.Cluster.exactTitle : Strings.Cluster.nearTitle
    let category: ShotCategory = kind == .exact ? .exactDuplicate : .nearDuplicate
    return Label {
      Text(Strings.Cluster.header(title, Format.count(members.count)))
    } icon: {
      Image(systemName: category.symbolName)
        .foregroundStyle(category.tint)
    }
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(.secondary)
    .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder private var actions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Theme.Spacing.m) { actionButtons }
      VStack(alignment: .leading, spacing: Theme.Spacing.s) { actionButtons }
    }
    .font(.subheadline)
  }

  @ViewBuilder private var actionButtons: some View {
    Button(Strings.Cluster.compare, systemImage: "rectangle.split.2x1", action: onCompare)
      .disabled(members.count < 2)
    if kind == .near {
      Button(
        Strings.Cluster.selectOthers, systemImage: "checkmark.circle", action: onSelectOthers)
    }
  }

  private func memberCell(_ member: Member, index: Int) -> some View {
    let isKeeper = member.id == keeperID
    return Button {
      onSetKeeper(member.id)
    } label: {
      Color.clear
        .frame(width: cellWidth, height: cellWidth / Theme.thumbnailAspectRatio)
        .overlay { ThumbnailImage(id: member.id, pointSize: CGSize(width: 140, height: 250)) }
        .overlay(alignment: .bottomLeading) { caption(for: member) }
        .clipShape(.rect(cornerRadius: Theme.Radius.thumbnail))
        .overlay {
          RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
            .strokeBorder(
              isKeeper ? Theme.keep : (member.isSelected ? Theme.accent : .clear),
              lineWidth: 3)
        }
        .contentShape(.rect(cornerRadius: Theme.Radius.thumbnail))
    }
    .buttonStyle(.plain)
    .overlay(alignment: .topLeading) {
      if isKeeper {
        keeperTag
          .matchedGeometryEffect(id: "keeper", in: keeperNamespace)
          .padding(Theme.Spacing.xs)
      }
    }
    .overlay(alignment: .topTrailing) {
      if !isKeeper || member.isSelected {
        SelectionRing(isSelected: member.isSelected) { onToggle(member.id) }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Strings.Cluster.member(index + 1, members.count, member.spokenDate))
    .accessibilityValue(accessibilityValue(for: member, isKeeper: isKeeper))
    .accessibilityAddTraits(isKeeper ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction(named: Strings.Cluster.setKeeper) { onSetKeeper(member.id) }
    .accessibilityAction(
      named: member.isSelected ? Strings.Grid.selectNone : Strings.Detail.select
    ) { onToggle(member.id) }
  }

  private func accessibilityValue(for member: Member, isKeeper: Bool) -> String {
    var parts: [String] = []
    if isKeeper { parts.append("\(Strings.Cluster.isKeeper), \(keeperNote)") }
    if member.isReceipt { parts.append(Strings.Cluster.receipt) }
    parts.append(member.isSelected ? Strings.Grid.selected : Strings.Grid.notSelected)
    return parts.joined(separator: ", ")
  }

  private var keeperTag: some View {
    VStack(alignment: .leading, spacing: 0) {
      Label(Strings.Cluster.keeperTag, systemImage: "checkmark")
        .font(.caption2.weight(.bold))
      Text(keeperNote)
        .font(.caption2)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(Theme.keep, in: .rect(cornerRadius: 6))
  }

  private func caption(for member: Member) -> some View {
    HStack(spacing: 2) {
      if member.isReceipt {
        Image(systemName: "checkmark.shield.fill")
      }
      Text(member.dateText)
        .lineLimit(1)
    }
    .font(.caption2.weight(.semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .background(.black.opacity(0.6), in: .rect(cornerRadius: 5))
    .padding(Theme.Spacing.xs)
  }
}
