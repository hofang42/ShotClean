import ShotCleanCore
import SwiftUI

/// One duplicate cluster (S6) as a horizontal row. The keeper has a keep-colored border and a
/// "Giữ" tag that moves with `matchedGeometryEffect`. Tapping a photo toggles its deletion — the
/// keeper included, so a whole cluster can go; long press (context menu) makes it the keeper.
/// Two clear row actions: "Giữ 1 ảnh tốt nhất" and "Xoá cả nhóm" / "Bỏ chọn nhóm".
struct ClusterRow: View {
  struct Member: Identifiable {
    let id: String
    let dateText: String
    let spokenDate: String
    let isReceipt: Bool
    /// Receipts, protected and undated photos are excluded from the row's bulk actions.
    let isBulkSelectable: Bool
    let isSelected: Bool
  }

  let kind: Cluster.Kind
  let members: [Member]
  let keeperID: String
  /// "Cũ nhất" / "Nét nhất" / "Bạn chọn".
  let keeperNote: String
  let onSetKeeper: (String) -> Void
  let onToggle: (String) -> Void
  /// Selects every member but the keeper and deselects the keeper ("Giữ 1 ảnh tốt nhất").
  let onSelectOthers: () -> Void
  /// Selects every member, the keeper included (receipts excluded).
  let onSelectAll: () -> Void
  /// Deselects every member.
  let onSelectNone: () -> Void
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
    let title = kind.rowTitle
    let category = kind.category
    return HStack {
      Label {
        Text(Strings.Cluster.header(title, Format.count(members.count)))
      } icon: {
        Image(systemName: category.symbolName)
          .foregroundStyle(category.tint)
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.secondary)
      .accessibilityAddTraits(.isHeader)
      Spacer(minLength: Theme.Spacing.s)
      Button(action: onCompare) {
        Image(systemName: "rectangle.split.2x1")
          .font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .contentShape(.rect)
      }
      .disabled(members.count < 2)
      .accessibilityLabel(Strings.Cluster.compare)
    }
  }

  @ViewBuilder private var actions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Theme.Spacing.s) { actionButtons }
      VStack(spacing: Theme.Spacing.s) { actionButtons }
    }
    .font(.subheadline.weight(.semibold))
    .buttonStyle(.bordered)
    .controlSize(.large)
    .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
  }

  @ViewBuilder private var actionButtons: some View {
    let others = members.filter { $0.id != keeperID }
    let keepsBest =
      !others.isEmpty && !members.contains(where: { $0.id == keeperID && $0.isSelected })
      && others.allSatisfy({ $0.isSelected || !$0.isBulkSelectable })
    Button(action: onSelectOthers) {
      Label(Strings.Cluster.keepBest, systemImage: keepsBest ? "checkmark.circle.fill" : "star")
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }
    .tint(Theme.keep)
    // Receipts and protected photos are never bulk-selected, so they do not count for "whole
    // cluster selected".
    let deletable = members.filter(\.isBulkSelectable)
    if !deletable.isEmpty {
      if deletable.allSatisfy(\.isSelected) {
        Button(action: onSelectNone) {
          Label(Strings.Cluster.selectNone, systemImage: "xmark.circle")
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
      } else {
        Button(role: .destructive, action: onSelectAll) {
          Label(Strings.Cluster.selectAll, systemImage: "trash")
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
        .tint(Theme.destructive)
      }
    }
  }

  private func memberCell(_ member: Member, index: Int) -> some View {
    let isKeeper = member.id == keeperID
    return Button {
      onToggle(member.id)
    } label: {
      Color.clear
        .frame(width: cellWidth, height: cellWidth / Theme.thumbnailAspectRatio)
        .overlay { ThumbnailImage(id: member.id, pointSize: CGSize(width: 140, height: 250)) }
        .overlay(alignment: .bottomLeading) { caption(for: member) }
        .overlay {
          if member.isSelected {
            Theme.accent.opacity(0.18)
          }
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.thumbnail))
        .overlay {
          RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
            .strokeBorder(
              member.isSelected ? Theme.accent : (isKeeper ? Theme.keep : .clear),
              lineWidth: 4)
        }
        .overlay(alignment: .topTrailing) {
          SelectionRing(isSelected: member.isSelected)
        }
        .contentShape(.rect(cornerRadius: Theme.Radius.thumbnail))
    }
    .buttonStyle(.plain)
    .contextMenu {
      if !isKeeper {
        Button(Strings.Cluster.setKeeper, systemImage: "star") { onSetKeeper(member.id) }
      }
      Button(
        member.isSelected ? Strings.Detail.deselect : Strings.Detail.select,
        systemImage: member.isSelected ? "xmark.circle" : "checkmark.circle"
      ) { onToggle(member.id) }
      Button(Strings.Cluster.compare, systemImage: "rectangle.split.2x1", action: onCompare)
    }
    .overlay(alignment: .topLeading) {
      if isKeeper && !member.isSelected {
        keeperTag
          .matchedGeometryEffect(id: "keeper", in: keeperNamespace)
          .padding(Theme.Spacing.xs)
          .allowsHitTesting(false)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Strings.Cluster.member(index + 1, members.count, member.spokenDate))
    .accessibilityValue(accessibilityValue(for: member, isKeeper: isKeeper))
    .accessibilityAddTraits(member.isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction { onToggle(member.id) }
    .accessibilityAction(named: Strings.Cluster.setKeeper) { onSetKeeper(member.id) }
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
