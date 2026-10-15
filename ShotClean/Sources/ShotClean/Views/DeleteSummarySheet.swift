import ShotCleanCore
import SwiftUI

/// S8 step 1: summary sheet ("Xoá N ảnh · ~X · Đã xoá gần đây 30 ngày"). Tapping "Xoá" calls
/// `AppModel.delete`, which shows the iOS confirmation dialog. No extra alert is stacked.
/// On success the sheet switches to `ResultView`.
struct DeleteSummarySheet: View {
  private enum Outcome {
    case deleted(count: Int, bytes: Int64)
    case cancelled
    case nothingToDelete
    case failed(String)
  }

  let pending: PendingDeletion

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var isDeleting = false
  @State private var outcome: Outcome?

  var body: some View {
    NavigationStack {
      Group {
        if case .deleted(let count, let bytes) = outcome {
          ResultView(deletedCount: count, bytes: bytes)
        } else {
          summary
        }
      }
      .toolbar {
        if !isDeleting, !isFinished {
          ToolbarItem(placement: .cancellationAction) {
            Button(Strings.cancel) { dismiss() }
          }
        }
      }
    }
    .presentationDetents(isFinished ? [.large] : [.medium, .large])
    .interactiveDismissDisabled(isDeleting)
  }

  private var isFinished: Bool {
    if case .deleted = outcome { return true }
    return false
  }

  private var summary: some View {
    let bytes = model.result?.reclaimableBytes(pending.ids, sizes: model.sizes) ?? 0
    let breakdown = categoryBreakdown()

    return ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.l) {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
          Text(Strings.Deletion.title(Format.count(pending.ids.count)))
            .font(.title.bold())
            .fontDesign(.rounded)
            .monospacedDigit()
          if bytes > 0 {
            Text(Strings.Deletion.size(Format.bytes(bytes)))
              .font(.title3)
              .fontDesign(.rounded)
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .combine)

        if !breakdown.isEmpty {
          VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(breakdown, id: \.category) { item in
              Label {
                Text("\(item.category.title): \(Format.count(item.count))")
              } icon: {
                Image(systemName: item.category.symbolName)
                  .foregroundStyle(item.category.tint)
              }
              .font(.subheadline)
            }
          }
        }

        Label(Strings.Deletion.recentlyDeletedNote, systemImage: "clock.arrow.circlepath")
          .font(.footnote)
          .foregroundStyle(.secondary)

        if let message = outcomeMessage {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        Button(role: .destructive) {
          performDelete(expectedBytes: bytes)
        } label: {
          HStack {
            if isDeleting {
              ProgressView()
            }
            Label(Strings.Deletion.confirm, systemImage: "trash")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.destructive)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
        .disabled(isDeleting || pending.ids.isEmpty)
      }
      .padding(Theme.Spacing.xl)
    }
  }

  private var outcomeMessage: String? {
    switch outcome {
    case .cancelled: Strings.Deletion.cancelled
    case .nothingToDelete: Strings.Deletion.nothingToDelete
    case .failed(let message): Strings.Deletion.failed(message)
    case .deleted, nil: nil
    }
  }

  private func categoryBreakdown() -> [(category: ShotCategory, count: Int)] {
    guard let verdicts = model.result?.verdicts else { return [] }
    var counts: [ShotCategory: Int] = [:]
    for id in pending.ids {
      if let category = verdicts[id]?.category {
        counts[category, default: 0] += 1
      }
    }
    return ShotCategory.allCases.compactMap { category in
      counts[category].map { (category, $0) }
    }
  }

  private func performDelete(expectedBytes: Int64) {
    isDeleting = true
    outcome = nil
    Task {
      do {
        switch try await model.delete(pending.ids) {
        case .deleted(let deleted):
          // Approximate if some assets were already gone.
          let bytes =
            deleted == pending.ids.count
            ? expectedBytes
            : expectedBytes * Int64(deleted) / Int64(max(pending.ids.count, 1))
          outcome = .deleted(count: deleted, bytes: bytes)
        case .cancelled:
          outcome = .cancelled
        case .nothingToDelete:
          outcome = .nothingToDelete
        }
      } catch {
        outcome = .failed(error.localizedDescription)
      }
      isDeleting = false
    }
  }
}
