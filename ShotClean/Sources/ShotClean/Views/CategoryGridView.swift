import ShotCleanCore
import SwiftUI

/// S5: adaptive grid of one category with reason badges, tap-to-select, drag-to-select (a
/// mostly horizontal drag starting on a cell; the first cell decides select vs deselect), sort
/// and a sticky bar with "Chọn tất cả / Bỏ chọn" and the destructive button. Selection lives in
/// `AppModel.selection`; bulk gestures never select receipts, protected or undated assets.
struct CategoryGridView: View {
  enum SortOrder: Hashable {
    case oldest, largest
  }

  let category: ShotCategory

  @Environment(AppModel.self) private var model
  @Environment(AppRouter.self) private var router
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var sortOrder = SortOrder.oldest
  @State private var dragSelect = DragSelect.idle
  @State private var gridWidth: CGFloat = 0

  /// Drag-to-select state: `selecting` remembers the mode (select / deselect) and the cell index
  /// the drag started on; a drag that starts vertically is left to the scroll view.
  private enum DragSelect: Equatable {
    case idle
    case scrolling
    case selecting(select: Bool, anchor: Int)
  }

  private var minimumCellWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 150 : 104 }

  private var columns: [GridItem] {
    [GridItem(.adaptive(minimum: minimumCellWidth), spacing: Theme.Spacing.s)]
  }

  private var isDragSelecting: Bool {
    if case .selecting = dragSelect { return true }
    return false
  }

  private var sortedIDs: [String] {
    guard let result = model.result else { return [] }
    let ids = result.ids(in: category)
    switch sortOrder {
    case .oldest:
      return ids.sorted { date(of: $0) < date(of: $1) }
    case .largest:
      return ids.sorted { (model.sizes[$0] ?? 0) > (model.sizes[$1] ?? 0) }
    }
  }

  var body: some View {
    let ids = sortedIDs
    let selected = model.selection.intersection(ids)

    ScrollView {
      Label(
        category == .transferReceipt ? Strings.Grid.receiptNote : Strings.Grid.dragHint,
        systemImage: category == .transferReceipt ? "checkmark.shield" : "hand.draw"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Theme.Spacing.l)
      .padding(.top, Theme.Spacing.s)
      LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
        ForEach(ids, id: \.self) { id in
          ThumbnailCell(
            id: id,
            reason: reason(of: id),
            accessibilityText: accessibilityText(of: id),
            isSelected: selected.contains(id),
            onToggle: { toggle(id) },
            onOpen: { router.path.append(.detail(id)) }
          )
        }
      }
      .background {
        GeometryReader { proxy in
          Color.clear
            .onAppear { gridWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in gridWidth = width }
        }
      }
      .simultaneousGesture(dragGesture(ids: ids))
      .padding(Theme.Spacing.l)
    }
    .scrollDisabled(isDragSelecting)
    .sensoryFeedback(.selection, trigger: selected.count)
    .overlay {
      if ids.isEmpty {
        ContentUnavailableView(Strings.Grid.empty, systemImage: category.symbolName)
      }
    }
    .background(Theme.background)
    .navigationTitle(category.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Menu {
          Picker(Strings.Grid.sort, selection: $sortOrder) {
            Text(Strings.Grid.sortOldest).tag(SortOrder.oldest)
            Text(Strings.Grid.sortLargest).tag(SortOrder.largest)
          }
        } label: {
          Label(Strings.Grid.sort, systemImage: "arrow.up.arrow.down")
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if !ids.isEmpty {
        let bytes = model.result?.reclaimableBytes(selected, sizes: model.sizes) ?? 0
        // Receipts, protected and undated photos are never bulk-selected (US6); they can still
        // be picked one by one.
        let bulkIDs = ids.filter(model.isBulkSelectable)
        let showsSelectNone =
          !selected.isEmpty && (bulkIDs.isEmpty || bulkIDs.allSatisfy(selected.contains))
        FloatingActionBar {
          Button {
            if showsSelectNone {
              model.setSelected(false, for: selected)
            } else {
              model.setSelected(true, for: bulkIDs)
            }
          } label: {
            Label(
              showsSelectNone ? Strings.Grid.selectNone : Strings.Grid.selectAll,
              systemImage: showsSelectNone ? "xmark.circle" : "checkmark.circle")
          }
          .buttonStyle(.bordered)
          .fixedSize()
          .disabled(!showsSelectNone && bulkIDs.isEmpty)

          Button(role: .destructive) {
            router.requestDeletion(of: selected)
          } label: {
            Label(
              Strings.Grid.deleteButton(Format.count(selected.count), Format.bytes(bytes)),
              systemImage: "trash"
            )
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(Theme.destructive)
          .disabled(selected.isEmpty)
        }
      }
    }
  }

  private func toggle(_ id: String) {
    model.toggleSelection(id)
  }

  private func dragGesture(ids: [String]) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        if dragSelect == .idle {
          let translation = value.translation
          if abs(translation.width) > abs(translation.height),
            let anchor = index(at: value.startLocation, count: ids.count)
          {
            dragSelect = .selecting(select: !model.selection.contains(ids[anchor]), anchor: anchor)
          } else {
            dragSelect = .scrolling
          }
        }
        guard case .selecting(let select, let anchor) = dragSelect,
          let current = index(at: value.location, count: ids.count)
        else { return }
        let range = min(anchor, current)...max(anchor, current)
        let rangeIDs = range.map { ids[$0] }
        if select {
          let added = rangeIDs.filter { !model.selection.contains($0) && model.isBulkSelectable($0) }
          if !added.isEmpty { model.setSelected(true, for: added) }
        } else {
          let removed = rangeIDs.filter { model.selection.contains($0) }
          if !removed.isEmpty { model.setSelected(false, for: removed) }
        }
      }
      .onEnded { _ in dragSelect = .idle }
  }

  /// Cell index under `point` (grid coordinates), mirroring the adaptive `LazyVGrid` layout:
  /// as many columns of at least `minimumCellWidth` as fit, cells sized by the thumbnail ratio.
  private func index(at point: CGPoint, count: Int) -> Int? {
    guard gridWidth > 0, count > 0, point.y >= 0 else { return nil }
    let spacing = Theme.Spacing.s
    let columnCount = max(1, Int((gridWidth + spacing) / (minimumCellWidth + spacing)))
    let cellWidth = (gridWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
    let cellHeight = cellWidth / Theme.thumbnailAspectRatio
    let column = min(columnCount - 1, max(0, Int(point.x / (cellWidth + spacing))))
    let row = Int(point.y / (cellHeight + spacing))
    let index = row * columnCount + column
    return index < count ? index : nil
  }

  private func date(of id: String) -> Date {
    model.captureDate(for: id) ?? CaptureDate.unknown
  }

  private func reason(of id: String) -> String {
    model.result?.verdicts[id]?.reason ?? ""
  }

  private func accessibilityText(of id: String) -> String {
    var parts = [category.title]
    let reason = reason(of: id)
    if !reason.isEmpty { parts.append(reason) }
    if let date = model.captureDate(for: id) {
      parts.append(Strings.Swipe.captured(Format.spokenDate(date)))
    }
    return parts.joined(separator: ". ")
  }
}
