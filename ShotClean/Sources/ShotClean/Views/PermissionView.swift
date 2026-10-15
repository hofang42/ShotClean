import SwiftUI

/// S2: explains why full library access is needed, then shows the system prompt.
struct PermissionView: View {
  @Environment(AppModel.self) private var model
  @State private var isRequesting = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
        Image(systemName: "photo.on.rectangle.angled")
          .font(.system(size: 56))
          .foregroundStyle(Theme.accent)
          .frame(maxWidth: .infinity)
          .padding(.top, Theme.Spacing.xl)
          .accessibilityHidden(true)

        Text(Strings.Permission.title)
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)

        Text(Strings.Permission.message)
          .font(.body)

        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
          point(Strings.Permission.pointReadOnly, symbol: "camera.viewfinder")
          point(Strings.Permission.pointNoUpload, symbol: "lock.shield")
          point(Strings.Permission.pointConfirm, symbol: "hand.raised")
        }

        Text(Strings.Permission.limitedHint)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, Theme.Spacing.xl)
      .padding(.bottom, Theme.Spacing.xl)
    }
    .background(Theme.background)
    .safeAreaInset(edge: .bottom) {
      Button {
        isRequesting = true
        Task {
          await model.requestPermission()
          isRequesting = false
        }
      } label: {
        Text(Strings.Permission.allow)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
      .disabled(isRequesting)
      .padding(.horizontal, Theme.Spacing.xl)
      .padding(.bottom, Theme.Spacing.s)
      .background(Theme.background)
    }
  }

  private func point(_ text: String, symbol: String) -> some View {
    Label {
      Text(text)
    } icon: {
      Image(systemName: symbol)
        .foregroundStyle(Theme.keep)
    }
    .font(.subheadline)
  }
}
