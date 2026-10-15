import SwiftUI
import UIKit

/// E1: access denied or restricted. Returning from Settings is handled by `RootView`.
struct PermissionDeniedView: View {
  @Environment(\.openURL) private var openURL

  var body: some View {
    ContentUnavailableView {
      Label(Strings.Permission.deniedTitle, systemImage: "lock.slash")
    } description: {
      Text(Strings.Permission.deniedMessage)
    } actions: {
      Button(Strings.openSettings) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          openURL(url)
        }
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.button))
    }
    .background(Theme.background)
  }
}
