import SwiftUI

/// Draggable card for swipe mode (S7). Drag left past the threshold queues a delete, right
/// keeps. Overlays use a label and symbol, not color alone. With Reduce Motion the card does
/// not rotate or fly away. VoiceOver gets "Giữ" / "Xoá" custom actions instead of the gesture.
struct SwipeCard: View {
  let id: String
  let title: String
  let reason: String
  let dateText: String?
  let accessibilityText: String
  var isInteractive = true
  /// Called once per decision. Swipes call it after the fly-away animation; VoiceOver actions
  /// call it immediately.
  let onDecision: (SwipeAction) -> Void
  /// Called when a swipe decision starts animating, so the parent can block other input (REV-2).
  var onLeave: () -> Void = {}

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var offset: CGSize = .zero
  /// Set while the card flies away; the decision is delivered by `.task(id:)`, which is
  /// cancelled if the card leaves the hierarchy first (REV-2).
  @State private var leavingAction: SwipeAction?

  private let threshold: CGFloat = 110

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      Color.clear
        .aspectRatio(Theme.thumbnailAspectRatio, contentMode: .fit)
        .overlay { ThumbnailImage(id: id, pointSize: CGSize(width: 320, height: 570)) }
        .clipShape(.rect(cornerRadius: Theme.Radius.thumbnail))
        .frame(maxWidth: .infinity)
        .layoutPriority(-1)

      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      if !reason.isEmpty {
        Text(reason)
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let dateText {
        Text(dateText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(Theme.Spacing.m)
    .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
    .overlay { decisionOverlay }
    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    .offset(x: offset.width, y: reduceMotion ? 0 : offset.height * 0.2)
    .rotationEffect(.degrees(reduceMotion ? 0 : Double(offset.width) / 25))
    .gesture(drag, including: isInteractive && leavingAction == nil ? .all : .subviews)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityHint(Strings.Swipe.hint)
    .accessibilityAction(named: Strings.keep) { decideNow(.keep) }
    .accessibilityAction(named: Strings.delete) { decideNow(.delete) }
    .task(id: leavingAction) {
      guard let action = leavingAction else { return }
      do {
        try await Task.sleep(for: .milliseconds(200))
      } catch {
        return
      }
      onDecision(action)
    }
  }

  @ViewBuilder private var decisionOverlay: some View {
    let progress = min(abs(offset.width) / threshold, 1)
    if offset.width < 0 {
      overlayLabel(Strings.delete, symbol: "trash.fill", color: Theme.destructive)
        .opacity(progress)
    } else if offset.width > 0 {
      overlayLabel(Strings.keep, symbol: "checkmark", color: Theme.keep)
        .opacity(progress)
    }
  }

  private func overlayLabel(_ text: String, symbol: String, color: Color) -> some View {
    RoundedRectangle(cornerRadius: Theme.Radius.card)
      .fill(color.opacity(0.18))
      .overlay {
        RoundedRectangle(cornerRadius: Theme.Radius.card)
          .strokeBorder(color, lineWidth: 3)
      }
      .overlay {
        Label(text, systemImage: symbol)
          .font(.title.bold())
          .foregroundStyle(.white)
          .padding(.horizontal, Theme.Spacing.l)
          .padding(.vertical, Theme.Spacing.s)
          .background(color, in: .capsule)
      }
      .allowsHitTesting(false)
  }

  private var drag: some Gesture {
    DragGesture()
      .onChanged { value in
        offset = value.translation
      }
      .onEnded { value in
        let width = value.translation.width
        if width <= -threshold {
          finish(.delete)
        } else if width >= threshold {
          finish(.keep)
        } else {
          withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
            offset = .zero
          }
        }
      }
  }

  private func finish(_ action: SwipeAction) {
    guard leavingAction == nil else { return }
    guard !reduceMotion else {
      onDecision(action)
      return
    }
    onLeave()
    let direction: CGFloat = action == .delete ? -1 : 1
    withAnimation(.easeIn(duration: 0.2)) {
      offset = CGSize(width: direction * 600, height: offset.height)
    }
    leavingAction = action
  }

  private func decideNow(_ action: SwipeAction) {
    guard isInteractive, leavingAction == nil else { return }
    onDecision(action)
  }
}
