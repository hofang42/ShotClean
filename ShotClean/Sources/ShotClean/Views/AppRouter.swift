import Observation

/// View-layer navigation state: the overview stack path and the single S8 presentation point.
@MainActor
@Observable
final class AppRouter {
  var path: [Route] = []
  var pendingDeletion: PendingDeletion?

  func requestDeletion(of ids: Set<String>) {
    guard !ids.isEmpty else { return }
    pendingDeletion = PendingDeletion(ids: ids)
  }
}
