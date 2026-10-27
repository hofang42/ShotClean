import ShotCleanCore
import SwiftUI

/// S6: duplicate and burst clusters, one horizontal row each. Exact / burst: non-keepers come
/// preselected. Near: preselected only when enabled in settings. Tapping a photo toggles it;
/// long press makes it the keeper (the new keeper is deselected; for exact and burst clusters
/// the previous keeper is selected instead, never a receipt or protected asset). The keeper can
/// be selected too, so a whole cluster can be deleted. "Giữ ảnh tốt nhất ở mọi nhóm" keeps every
/// keeper and selects the rest in one tap. Bulk selection never includes receipts, protected or
/// undated assets.
struct ClusterReviewView: View {
  private struct Comparison: Identifiable {
    let id = UUID()
    let keeperID: String
    let otherIDs: [String]
  }

  let kind: Cluster.Kind

  @Environment(AppModel.self) private var model
  @Environment(AppRouter.self) private var router
  @State private var comparison: Comparison?

  private var kindClusters: [Cluster] {
    model.result?.clusters.filter { $0.kind == kind } ?? []
  }

  var body: some View {
    let clusters = kindClusters
    let memberIDs = Set(clusters.flatMap(\.memberIDs))
    let selected = model.selection.intersection(memberIDs)

    ScrollView {
      LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
        Text(kind.intro)
          .font(.footnote)
          .foregroundStyle(.secondary)

        if !clusters.isEmpty {
          HStack(spacing: Theme.Spacing.s) {
            // Every cluster keeps its keeper here; deleting a whole cluster stays a per-row
            // decision ("Xoá cả nhóm"), so one tap can never wipe every copy of every photo.
            Button {
              for cluster in clusters { keepBest(in: cluster) }
            } label: {
              Label(Strings.Cluster.keepBestEverywhere, systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.keep)

            Button {
              model.setSelected(false, for: selected)
            } label: {
              Label(Strings.Grid.selectNone, systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(selected.isEmpty)
          }
          .font(.subheadline.weight(.semibold))
          .controlSize(.large)
          .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
        }

        ForEach(clusters, id: \.keeperID) { cluster in
          let keeperID = model.keeper(of: cluster)
          ClusterRow(
            kind: kind,
            members: members(of: cluster),
            keeperID: keeperID,
            keeperNote: keeperNote(cluster: cluster, keeper: keeperID),
            onSetKeeper: { model.setKeeper($0, in: cluster) },
            onToggle: { model.toggleSelection($0) },
            onSelectOthers: { keepBest(in: cluster) },
            onSelectAll: {
              // Bulk selection never includes receipts, protected or undated assets; they can
              // still be picked one by one.
              model.setSelected(true, for: cluster.memberIDs.filter(model.isBulkSelectable))
            },
            onSelectNone: { model.setSelected(false, for: cluster.memberIDs) },
            onCompare: {
              comparison = Comparison(
                keeperID: keeperID, otherIDs: cluster.memberIDs.filter { $0 != keeperID })
            }
          )
        }
      }
      .padding(Theme.Spacing.l)
    }
    .overlay {
      if clusters.isEmpty {
        ContentUnavailableView(
          Strings.Cluster.empty,
          systemImage: kind.category.symbolName)
      }
    }
    .background(Theme.background)
    .navigationTitle(kind.category.title)
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if !clusters.isEmpty {
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
    .sensoryFeedback(.selection, trigger: selected.count)
    .sheet(item: $comparison) { comparison in
      CompareView(keeperID: comparison.keeperID, otherIDs: comparison.otherIDs)
    }
  }

  private func keeperNote(cluster: Cluster, keeper: String) -> String {
    guard keeper == cluster.keeperID else { return Strings.Cluster.keeperChosen }
    if model.isProtected(keeper) { return Strings.Cluster.keeperProtected }
    return cluster.kind.coreKeeperNote
  }

  /// Keeps the cluster's keeper and selects every other bulk-selectable member.
  private func keepBest(in cluster: Cluster) {
    let keeperID = model.keeper(of: cluster)
    if model.selection.contains(keeperID) {
      model.setSelected(false, for: [keeperID])
    }
    let extras = cluster.memberIDs.filter {
      $0 != keeperID && !model.selection.contains($0) && model.isBulkSelectable($0)
    }
    if !extras.isEmpty { model.setSelected(true, for: extras) }
  }

  private func members(of cluster: Cluster) -> [ClusterRow.Member] {
    cluster.memberIDs.map { id in
      let date = model.captureDate(for: id)
      return ClusterRow.Member(
        id: id,
        dateText: date.map(Format.date) ?? "",
        spokenDate: date.map(Format.spokenDate) ?? "",
        isReceipt: model.result?.verdicts[id]?.category == .transferReceipt,
        isBulkSelectable: model.isBulkSelectable(id),
        isSelected: model.selection.contains(id)
      )
    }
  }
}
