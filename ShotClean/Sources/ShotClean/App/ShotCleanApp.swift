import SwiftUI

@main
struct ShotCleanApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      RootPlaceholderView()
        .environment(model)
    }
  }
}
