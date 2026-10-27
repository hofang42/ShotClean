import ShotCleanCore
import SwiftUI

/// S6: duplicate clusters, one horizontal row each. Exact: non-keepers come preselected. Near:
/// preselected only when enabled in settings. Changing the keeper deselects the new keeper; for
/// exact clusters the previous keeper is selected instead (never a receipt). The keeper can be
/// selected too, so a whole cluster can be deleted.
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
        Text(kind == .exact ? Strings.Cluster.exactIntro : Strings.Cluster.nearIntro)
          .font(.footnote)
          .foregroundStyle(.secondary)

        if clusters.count > 1 {
          HStack {
            // Every cluster keeps its keeper here; deleting a whole cluster stays a per-row
            // decision ("Xoá cả nhóm"), so one tap can never wipe every copy of every photo.
            Button(Strings.Cluster.selectAllClusters, systemImage: "checkmark.circle.fill") {
              let verdicts = model.result?.verdicts ?? [:]
              let extras = clusters.flatMap { cluster in
                let keeperID = model.keeper(of: cluster)
                return cluster.memberIDs.filter {
                  $0 != keeperID && verdicts[$0]?.category != .transferReceipt
                }
              }
              model.setSelected(true, for: extras)
            }
            Spacer()
            Button(Strings.Grid.selectNone, systemImage: "xmark.circle") {
              model.setSelected(false, for: memberIDs)
            }
          }
          .font(.subheadline)
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
            onSelectOthers: {
              // Bulk selection never includes receipts; they can still be picked one by one.
              let verdicts = model.result?.verdicts ?? [:]
              model.setSelected(
                true,
                for: cluster.memberIDs.filter {
                  $0 != keeperID && verdicts[$0]?.category != .transferReceipt
                })
            },
            onSelectAll: {
              let verdicts = model.result?.verdicts ?? [:]
              model.setSelected(
                true,
                for: cluster.memberIDs.filter { verdicts[$0]?.category != .transferReceipt })
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

  private func keeperNote(cluster: Cluster, keeper: String) -> String {
    guard keeper == cluster.keeperID else { return Strings.Cluster.keeperChosen }
    return cluster.kind == .exact ? Strings.Cluster.keeperOldest : Strings.Cluster.keeperLargest
  }

  private func members(of cluster: Cluster) -> [ClusterRow.Member] {
    cluster.memberIDs.map { id in
      let date = model.captureDate(for: id)
      return ClusterRow.Member(
        id: id,
        dateText: date.map(Format.date) ?? "",
        spokenDate: date.map(Format.spokenDate) ?? "",
        isReceipt: model.result?.verdicts[id]?.category == .transferReceipt,
        isSelected: model.selection.contains(id)
      )
    }
  }
}
