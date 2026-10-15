import ShotCleanCore
import SwiftUI

/// S7: one card at a time from `AppModel.swipeQueue`. Swiping or the buttons only queue a
/// decision; "Xong" opens the S8 summary for the delete queue. Undo walks back one decision.
struct SwipeReviewView: View {
  private struct Decision: Equatable {
    let id: String
    let action: SwipeAction
  }

  /// Haptic trigger; `serial` makes repeated identical actions distinct.
  private struct FeedbackEvent: Equatable {
    enum Kind { case idle, keep, delete, undo }
    var serial = 0
    var kind = Kind.idle
  }

  @Environment(AppModel.self) private var model
  @Environment(AppRouter.self) private var router
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var items: [String]?
  @State private var history: [Decision] = []
  @State private var feedback = FeedbackEvent()

  var body: some View {
    let queue = items ?? []
    let position = history.count
    let deleteIDs = history.filter { $0.action == .delete }.map(\.id)
    let bytes = model.result?.reclaimableBytes(Set(deleteIDs), sizes: model.sizes) ?? 0

    VStack(spacing: Theme.Spacing.m) {
      header(deleteCount: deleteIDs.count, bytes: bytes, position: position, total: queue.count)

      ZStack {
        if queue.isEmpty {
          ContentUnavailableView(
            Strings.Swipe.emptyTitle,
            systemImage: "hand.draw",
            description: Text(Strings.Swipe.emptyMessage))
        } else if position >= queue.count {
          ContentUnavailableView(
            Strings.Swipe.finishedTitle,
            systemImage: "checkmark.circle",
            description: Text(Strings.Swipe.finishedMessage(Format.count(deleteIDs.count))))
        } else {
          if queue.indices.contains(position + 1) {
            card(for: queue[position + 1], isInteractive: false)
              .scaleEffect(0.95)
              .offset(y: 12)
              .accessibilityHidden(true)
          }
          card(for: queue[position], isInteractive: true)
            .id(queue[position])
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
        }
      }
      .frame(maxHeight: .infinity)
      .padding(.horizontal, Theme.Spacing.l)
    }
    .padding(.top, Theme.Spacing.s)
    .background(Theme.background)
    .navigationTitle(Strings.Swipe.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(Strings.done) {
          router.requestDeletion(of: Set(deleteIDs))
        }
        .disabled(deleteIDs.isEmpty)
      }
    }
    .safeAreaInset(edge: .bottom) {
      FloatingActionBar {
        Button {
          decide(.delete)
        } label: {
          Label(Strings.delete, systemImage: "trash")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.destructive)
        .disabled(position >= queue.count)

        Button {
          undo()
        } label: {
          Label(Strings.undo, systemImage: "arrow.uturn.backward")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(history.isEmpty)

        Button {
          decide(.keep)
        } label: {
          Label(Strings.keep, systemImage: "checkmark")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.keep)
        .disabled(position >= queue.count)
      }
    }
    .sensoryFeedback(trigger: feedback) { _, event in
      switch event.kind {
      case .idle: nil
      case .keep: .selection
      case .delete: .impact(weight: .medium)
      case .undo: .impact(weight: .light)
      }
    }
    .onAppear {
      if self.items == nil {
        let known = model.result?.verdicts
        self.items = model.swipeQueue.filter { known?[$0] != nil }
      }
    }
  }

  private func header(deleteCount: Int, bytes: Int64, position: Int, total: Int) -> some View {
    HStack {
      Label(
        Strings.Swipe.queue(Format.count(deleteCount), Format.bytes(bytes)),
        systemImage: "trash"
      )
      .font(.subheadline.weight(.semibold))
      .monospacedDigit()
      .contentTransition(.numericText(value: Double(deleteCount)))
      Spacer()
      if total > 0 {
        Text(Strings.Swipe.position(min(position + 1, total), total))
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, Theme.Spacing.l)
    .accessibilityElement(children: .combine)
  }

  private func card(for id: String, isInteractive: Bool) -> some View {
    let verdict = model.result?.verdicts[id]
    let date = model.features(for: id)?.createdAt
    let title = verdict?.category.title ?? ""
    let reason = verdict?.reason ?? ""
    var spoken = [title, reason].filter { !$0.isEmpty }
    if let date { spoken.append(Strings.Swipe.captured(Format.spokenDate(date))) }

    return SwipeCard(
      id: id,
      title: title,
      reason: reason,
      dateText: date.map { Strings.Swipe.captured(Format.date($0)) },
      accessibilityText: spoken.joined(separator: ". "),
      isInteractive: isInteractive,
      onDecision: decide
    )
  }

  private func decide(_ action: SwipeAction) {
    guard let items, history.count < items.count else { return }
    let id = items[history.count]
    withAnimation(reduceMotion ? nil : .snappy) {
      history.append(Decision(id: id, action: action))
    }
    feedback = FeedbackEvent(serial: feedback.serial + 1, kind: action == .delete ? .delete : .keep)
  }

  private func undo() {
    guard !history.isEmpty else { return }
    withAnimation(reduceMotion ? nil : .snappy) {
      _ = history.removeLast()
    }
    feedback = FeedbackEvent(serial: feedback.serial + 1, kind: .undo)
  }
}
