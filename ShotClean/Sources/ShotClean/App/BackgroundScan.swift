import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

/// Keeps a running scan alive after the user leaves the app and tells them when it is done.
///
/// - iOS 26+: a `BGContinuedProcessingTask` is submitted when a scan with real work starts while
///   the app is in front. The system shows its progress outside the app and the user can cancel
///   it there; cancelling (or the system expiring it) stops the scan, finished work is kept.
/// - Any iOS: when a scan finishes while the app is not active, a local notification is posted.
///
/// It never starts a scan by itself and never deletes anything.
@MainActor
final class BackgroundScan {
  static let shared = BackgroundScan()

  /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
  static let taskIdentifier = "com.hofang42.ShotClean.scan"
  /// Scans with fewer pending items finish quickly; no system task for them.
  private static let minimumItems = 30

  /// The running `BGContinuedProcessingTask` (type-erased: the class exists from iOS 26 only).
  private var task: AnyObject?
  private var isRegistered = false
  private var onCancel: (() -> Void)?

  private init() {}

  // MARK: Continued processing

  /// A scan of `total` items starts. `onCancel` stops it when the user cancels from the
  /// system UI or the system expires the task.
  func scanStarted(total: Int, onCancel: @escaping () -> Void) {
    guard total >= Self.minimumItems,
      UIApplication.shared.applicationState == .active
    else { return }
    requestNotificationPermission()
    guard #available(iOS 26.0, *) else { return }
    self.onCancel = onCancel
    registerIfNeeded()
    let request = BGContinuedProcessingTaskRequest(
      identifier: Self.taskIdentifier,
      title: Strings.Background.title,
      subtitle: Strings.Background.progress(Format.count(0), Format.count(total)))
    // Never queue: a scan that cannot start right away simply runs in the app as before.
    request.strategy = .fail
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      Log.app.info(
        "Continued scan not started: \(error.localizedDescription, privacy: .public)")
    }
  }

  func progress(done: Int, total: Int) {
    guard #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask else { return }
    task.progress.totalUnitCount = Int64(total)
    task.progress.completedUnitCount = Int64(done)
    task.updateTitle(
      Strings.Background.title,
      subtitle: Strings.Background.progress(Format.count(done), Format.count(total)))
  }

  /// The scan ended. `deletable`/`bytes` describe what is now preselected, for the notification.
  func scanFinished(completed: Bool, deletable: Int, bytes: Int64) {
    if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
      task.setTaskCompleted(success: completed)
    }
    task = nil
    onCancel = nil
    guard completed, UIApplication.shared.applicationState != .active else { return }
    postFinishedNotification(deletable: deletable, bytes: bytes)
  }

  @available(iOS 26.0, *)
  private func registerIfNeeded() {
    guard !isRegistered else { return }
    // `.main`: the launch handler runs on the main queue, so it may touch main-actor state.
    isRegistered = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.taskIdentifier, using: .main
    ) { task in
      MainActor.assumeIsolated {
        BackgroundScan.shared.attach(task)
      }
    }
  }

  @available(iOS 26.0, *)
  private func attach(_ bgTask: BGTask) {
    guard let continued = bgTask as? BGContinuedProcessingTask else {
      bgTask.setTaskCompleted(success: false)
      return
    }
    // The scan may already be over (tiny libraries); nothing to keep alive then.
    guard onCancel != nil else {
      continued.setTaskCompleted(success: true)
      return
    }
    continued.expirationHandler = {
      Task { @MainActor in BackgroundScan.shared.expire() }
    }
    task = continued
  }

  private func expire() {
    Log.app.info("Continued scan cancelled or expired; stopping the scan")
    onCancel?()
    if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
      task.setTaskCompleted(success: false)
    }
    task = nil
    onCancel = nil
  }

  // MARK: Notification

  private func requestNotificationPermission() {
    Task {
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound,
      ])
    }
  }

  private func postFinishedNotification(deletable: Int, bytes: Int64) {
    let content = UNMutableNotificationContent()
    content.title = Strings.Background.doneTitle
    content.body =
      deletable > 0
      ? Strings.Background.doneBody(Format.count(deletable), Format.bytes(bytes))
      : Strings.Background.doneNothing
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: "scan-finished", content: content, trigger: nil)
    Task {
      try? await UNUserNotificationCenter.current().add(request)
    }
  }
}
