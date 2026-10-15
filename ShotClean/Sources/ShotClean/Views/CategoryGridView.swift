import ShotCleanCore
import SwiftUI

/// S5: adaptive grid of one category with reason badges, selection, select all/none, sort and
/// a sticky destructive bar. Selection lives in `AppModel.selection`, so preselection (and its
/// absence for receipts) comes from the Core.
struct CategoryGridView: View {
  enum SortOrder: Hashable {
    case oldest, largest
  }

  let category: ShotCategory

  @Environment(AppModel.self) private var model
  @Environment(AppRouter.self) private var router
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var sortOrder = SortOrder.oldest

  private var columns: [GridItem] {
    let minimum: CGFloat = dynamicTypeSize.isAccessibilitySize ? 150 : 104
    return [GridItem(.adaptive(minimum: minimum), spacing: Theme.Spacing.s)]
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
      if category == .transferReceipt {
        Label(Strings.Grid.receiptNote, systemImage: "checkmark.shield")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Theme.Spacing.l)
          .padding(.top, Theme.Spacing.s)
      }
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
      .padding(Theme.Spacing.l)
    }
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
        // Receipts: no bulk "select all"; each receipt must be picked deliberately (US6).
        let canSelectAll = category != .transferReceipt
        let showsSelectNone = !selected.isEmpty && (!canSelectAll || selected.count == ids.count)
        Button(showsSelectNone ? Strings.Grid.selectNone : Strings.Grid.selectAll) {
          if showsSelectNone {
            model.selection.subtract(ids)
          } else {
            model.selection.formUnion(ids)
          }
        }
        .disabled(ids.isEmpty || (!canSelectAll && selected.isEmpty))
      }
    }
    .safeAreaInset(edge: .bottom) {
      if !ids.isEmpty {
        let bytes = model.result?.reclaimableBytes(selected, sizes: model.sizes) ?? 0
        FloatingActionBar {
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
    if model.selection.contains(id) {
      model.selection.remove(id)
    } else {
      model.selection.insert(id)
    }
  }

  private func date(of id: String) -> Date {
    model.features(for: id)?.createdAt ?? .distantPast
  }

  private func reason(of id: String) -> String {
    model.result?.verdicts[id]?.reason ?? ""
  }

  private func accessibilityText(of id: String) -> String {
    var parts = [category.title]
    let reason = reason(of: id)
    if !reason.isEmpty { parts.append(reason) }
    if let date = model.features(for: id)?.createdAt {
      parts.append(Strings.Swipe.captured(Format.spokenDate(date)))
    }
    return parts.joined(separator: ". ")
  }
}
