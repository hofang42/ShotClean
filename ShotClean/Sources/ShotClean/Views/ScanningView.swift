import SwiftUI

/// S3: first scan, before any result exists. Large ring, numeric counter, cancel.
/// Cancelling keeps finished analyses; the model then moves to `.ready` with a partial result.
struct ScanningView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isCancelling = false

  private var progress: (done: Int, total: Int) {
    if case .scanning(let done, let total) = model.phase { return (done, total) }
    return (0, 0)
  }

  var body: some View {
    let done = progress.done
    let total = progress.total
    let fraction = total > 0 ? Double(done) / Double(total) : 0

    VStack(spacing: Theme.Spacing.xl) {
      Spacer()
      Text(Strings.Scan.title)
        .font(.title2.bold())
        .multilineTextAlignment(.center)

      ZStack {
        Circle()
          .stroke(Color(uiColor: .systemFill), lineWidth: 14)
        Circle()
          .trim(from: 0, to: fraction)
          .stroke(Theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(reduceMotion ? nil : .easeOut, value: fraction)
        if total > 0 {
          Text(Strings.Scan.progress(Format.count(done), Format.count(total)))
            .font(.title3.bold())
            .fontDesign(.rounded)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(done)))
            .animation(reduceMotion ? nil : .default, value: done)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(Theme.Spacing.xl)
        } else {
          ProgressView()
            .controlSize(.large)
        }
      }
      .frame(width: 180, height: 180)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Strings.Scan.accessibilityLabel)
      .accessibilityValue(
        total > 0
          ? Strings.Scan.progress(Format.count(done), Format.count(total))
          : Strings.Scan.finding)

      if total == 0 {
        Text(Strings.Scan.finding)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      PrivacyBadge()
      Spacer()
      Button(Strings.cancel, role: .cancel) {
        isCancelling = true
        model.cancelScan()
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .disabled(isCancelling)
      .padding(.bottom, Theme.Spacing.l)
    }
    .padding(.horizontal, Theme.Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
  }
}
