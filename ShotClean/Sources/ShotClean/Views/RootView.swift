import SwiftUI

/// Routes on `AppModel.phase`. The scan is a state of the overview: once a (cached) result
/// exists, the overview is shown while new screenshots are scanned in the background.
struct RootView: View {
  private enum Screen: Equatable {
    case onboarding, permission, denied, scanning, overview
  }

  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var router = AppRouter()

  private var screen: Screen {
    switch model.phase {
    case .needsOnboarding: .onboarding
    case .needsPermission: .permission
    case .denied: .denied
    case .scanning: model.result == nil ? .scanning : .overview
    case .ready: .overview
    }
  }

  var body: some View {
    ZStack {
      switch screen {
      case .onboarding:
        OnboardingView()
          .transition(.opacity)
      case .permission:
        PermissionView()
          .transition(.opacity)
      case .denied:
        PermissionDeniedView()
          .transition(.opacity)
      case .scanning:
        ScanningView()
          .transition(.opacity)
      case .overview:
        OverviewView()
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
      }
    }
    .animation(reduceMotion ? nil : .smooth, value: screen)
    .environment(router)
    .tint(Theme.accent)
    .sensoryFeedback(.success, trigger: model.phase) { oldPhase, newPhase in
      guard case .scanning = oldPhase else { return false }
      return newPhase == .ready
    }
    .task {
      if model.hasCompletedOnboarding { await model.start() }
    }
    .onChange(of: scenePhase) { _, newPhase in
      // E1 / REV-20: access may have changed in Settings, or new screenshots were taken.
      if newPhase == .active {
        Task { await model.refreshAfterForeground() }
      }
    }
  }
}
