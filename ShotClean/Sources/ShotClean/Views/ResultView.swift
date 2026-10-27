import SwiftUI

/// S8 step 3: counted-up freed space, animated checkmark, success haptic and the honest
/// "Recently Deleted" note. "Về Tổng quan" pops to the root and closes the sheet.
struct ResultView: View {
  let deletedCount: Int
  let bytes: Int64

  @Environment(AppRouter.self) private var router
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var displayedBytes: Int64 = 0
  @State private var didAppear = false

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.Spacing.l) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 72))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(Theme.keep)
          .symbolEffect(.bounce, value: didAppear)
          .accessibilityHidden(true)
          .padding(.top, Theme.Spacing.xl)

        Text(Strings.Deletion.resultTitle)
          .font(.title2.bold())
          .accessibilityAddTraits(.isHeader)

        if bytes > 0 {
          Text(Format.bytes(displayedBytes))
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.brandGradient)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(displayedBytes)))
            .accessibilityLabel(Format.bytes(bytes))
        }

        Text(Strings.Deletion.resultCount(Format.count(deletedCount)))
          .font(.body)
          .multilineTextAlignment(.center)

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
          Label(Strings.Deletion.honestNote, systemImage: "info.circle")
            .font(.subheadline)
          Text(Strings.Deletion.howTo)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
        .shadow(color: Theme.shadow, radius: 8, y: 2)

        Button {
          router.path = []
          dismiss()
        } label: {
          Text(Strings.Deletion.backToOverview)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
      }
      .padding(Theme.Spacing.xl)
    }
    .sensoryFeedback(.success, trigger: didAppear)
    .task {
      guard !didAppear else { return }
      didAppear = true
      await countUp()
    }
    .onDisappear {
      router.path = []
    }
  }

  private func countUp() async {
    guard !reduceMotion, bytes > 0 else {
      displayedBytes = bytes
      return
    }
    let steps = 20
    for step in 1...steps {
      try? await Task.sleep(for: .milliseconds(40))
      withAnimation(.snappy) {
        displayedBytes = bytes * Int64(step) / Int64(steps)
      }
    }
  }
}
