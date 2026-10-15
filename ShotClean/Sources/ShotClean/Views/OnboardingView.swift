import SwiftUI

/// S1: one screen, illustration, three benefits, "Bắt đầu".
struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @State private var isStarting = false

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.Spacing.xl) {
        illustration
          .padding(.top, Theme.Spacing.xl)

        Text(Strings.Onboarding.title)
          .font(.largeTitle.bold())
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
          benefit(Strings.Onboarding.benefitScreenshotsOnly, symbol: "camera.viewfinder")
          benefit(Strings.Onboarding.benefitOnDevice, symbol: "iphone")
          benefit(Strings.Onboarding.benefitReceipts, symbol: "checkmark.shield")
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        PrivacyBadge()
      }
      .padding(.horizontal, Theme.Spacing.xl)
      .padding(.bottom, Theme.Spacing.xl)
    }
    .background(Theme.background)
    .safeAreaInset(edge: .bottom) {
      Button {
        isStarting = true
        Task { await model.start() }
      } label: {
        Text(Strings.Onboarding.start)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
      .disabled(isStarting)
      .padding(.horizontal, Theme.Spacing.xl)
      .padding(.bottom, Theme.Spacing.s)
      .background(Theme.background)
    }
  }

  private var illustration: some View {
    ZStack {
      ForEach(0..<3) { index in
        RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
          .fill(Theme.card)
          .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
              .strokeBorder(.quaternary, lineWidth: 1)
          }
          .frame(width: 84, height: 150)
          .rotationEffect(.degrees(Double(index - 1) * 10))
          .offset(x: CGFloat(index - 1) * 46)
      }
      Image(systemName: "checkmark.shield.fill")
        .font(.system(size: 44))
        .foregroundStyle(Theme.keep)
        .padding(Theme.Spacing.m)
        .background(Theme.background, in: .circle)
        .offset(y: 60)
    }
    .frame(height: 210)
    .accessibilityHidden(true)
  }

  private func benefit(_ text: String, symbol: String) -> some View {
    Label {
      Text(text)
        .font(.body)
    } icon: {
      Image(systemName: symbol)
        .foregroundStyle(Theme.accent)
        .font(.title3)
    }
  }
}
