import ShotCleanCore
import SwiftUI

/// S6: duplicate clusters, one horizontal row each. Exact: non-keepers come preselected from
/// the Core. Near: nothing is preselected. Changing the keeper deselects the new keeper; for
/// exact clusters the previous keeper is selected instead (never a receipt).
struct ClusterReviewView: View {
  private struct Comparison: Identifiable {
    let id = UUID()
    let keeperID: String
    let otherIDs: [String]
  }

  let kind: Cluster.Kind

  @Environment(AppModel.self) private var model
  @Environment(AppRouter.self) private var router
  /// Original keeper id → keeper chosen by the user.
  @State private var keeperOverrides: [String: String] = [:]
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
        Text(kind == .exact ? Strings.Cluster.exactIntro : Strings.Cluster.nearIntro)
          .font(.footnote)
          .foregroundStyle(.secondary)

        ForEach(clusters, id: \.keeperID) { cluster in
          let keeperID = keeper(of: cluster)
          ClusterRow(
            kind: kind,
            members: members(of: cluster),
            keeperID: keeperID,
            keeperNote: keeperNote(cluster: cluster, keeper: keeperID),
            onSetKeeper: { setKeeper($0, in: cluster) },
            onToggle: toggle,
            onSelectOthers: {
              // Bulk selection never includes receipts; they can still be picked one by one.
              let verdicts = model.result?.verdicts ?? [:]
              model.selection.formUnion(
                cluster.memberIDs.filter {
                  $0 != keeperID && verdicts[$0]?.category != .transferReceipt
                })
            },
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
          systemImage: kind == .exact ? "doc.on.doc" : "square.on.square.dashed")
      }
    }
    .background(Theme.background)
    .navigationTitle(
      kind == .exact ? ShotCategory.exactDuplicate.title : ShotCategory.nearDuplicate.title
    )
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
    .sheet(item: $comparison) { comparison in
      CompareView(keeperID: comparison.keeperID, otherIDs: comparison.otherIDs)
    }
  }

  private func keeper(of cluster: Cluster) -> String {
    keeperOverrides[cluster.keeperID] ?? cluster.keeperID
  }

  private func keeperNote(cluster: Cluster, keeper: String) -> String {
    guard keeper == cluster.keeperID else { return Strings.Cluster.keeperChosen }
    return cluster.kind == .exact ? Strings.Cluster.keeperOldest : Strings.Cluster.keeperSharpest
  }

  private func members(of cluster: Cluster) -> [ClusterRow.Member] {
    cluster.memberIDs.map { id in
      let date = model.features(for: id)?.createdAt
      return ClusterRow.Member(
        id: id,
        dateText: date.map(Format.date) ?? "",
        spokenDate: date.map(Format.spokenDate) ?? "",
        isReceipt: model.result?.verdicts[id]?.category == .transferReceipt,
        isSelected: model.selection.contains(id)
      )
    }
  }

  private func setKeeper(_ newKeeper: String, in cluster: Cluster) {
    let oldKeeper = keeper(of: cluster)
    guard newKeeper != oldKeeper else { return }
    keeperOverrides[cluster.keeperID] = newKeeper
    model.selection.remove(newKeeper)
    // Exact duplicates: the previous keeper becomes a plain duplicate. Never auto-select a
    // receipt, and never auto-select anything in near-duplicate clusters.
    let oldIsReceipt = model.result?.verdicts[oldKeeper]?.category == .transferReceipt
    if cluster.kind == .exact, !oldIsReceipt {
      model.selection.insert(oldKeeper)
    }
  }

  private func toggle(_ id: String) {
    if model.selection.contains(id) {
      model.selection.remove(id)
    } else {
      model.selection.insert(id)
    }
  }
}
