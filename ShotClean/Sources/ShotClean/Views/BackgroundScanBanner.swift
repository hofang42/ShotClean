import SwiftUI

/// Small progress shown at the top of the overview while new screenshots are scanned
/// behind cached results. Renders nothing when no scan is running.
struct BackgroundScanBanner: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    if case .scanning(let done, let total) = model.phase {
      VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
        HStack {
          Text(
            total > 0
              ? Strings.Scan.newPhotos(Format.count(done), Format.count(total))
              : Strings.Scan.checkingNew
          )
          .font(.footnote)
          .monospacedDigit()
          .contentTransition(.numericText(value: Double(done)))
          Spacer()
          Button(Strings.cancel) { model.cancelScan() }
            .font(.footnote)
        }
        if total > 0 {
          ProgressView(value: Double(done), total: Double(total))
        }
      }
      .padding(Theme.Spacing.m)
      .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.button))
      .accessibilityElement(children: .combine)
    }
  }
}
