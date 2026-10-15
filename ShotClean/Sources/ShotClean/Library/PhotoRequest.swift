import os  // OSAllocatedUnfairLock

/// Bridges one cancellable PhotoKit request to async/await (REV-8, REV-16).
///
/// The continuation is resumed exactly once: by the first `finish` call, or with `cancelledValue`
/// when the task is cancelled (the PhotoKit request is cancelled too). Later callbacks are ignored.
/// Handlers given to PhotoKit must be formed in nonisolated code (PhotoKit calls them on its own
/// queues); `start` only receives a `@Sendable` `finish` to call from such a handler.
final class PhotoRequest<Value: Sendable>: Sendable {
  private struct State: Sendable {
    var continuation: CheckedContinuation<Value, Never>?
    var cancelRequest: (@Sendable () -> Void)?
    var isCancelled = false
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Starts the request with `start`, which returns a closure that cancels it.
  func run(
    isolation: isolated (any Actor)? = #isolation,
    cancelledValue: Value,
    start: (_ finish: @escaping @Sendable (Value) -> Void) -> @Sendable () -> Void
  ) async -> Value {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        guard install(continuation) else {
          continuation.resume(returning: cancelledValue)
          return
        }
        let cancel = start { [self] value in finish(value) }
        setCancel(cancel)
      }
    } onCancel: {
      cancel(with: cancelledValue)
    }
  }

  private func install(_ continuation: CheckedContinuation<Value, Never>) -> Bool {
    state.withLock { state in
      guard !state.isCancelled else { return false }
      state.continuation = continuation
      return true
    }
  }

  private func setCancel(_ cancel: @escaping @Sendable () -> Void) {
    let alreadyCancelled = state.withLock { state in
      guard !state.isCancelled else { return true }
      state.cancelRequest = cancel
      return false
    }
    if alreadyCancelled { cancel() }
  }

  private func finish(_ value: Value) {
    let continuation = state.withLock { state in
      defer {
        state.continuation = nil
        state.cancelRequest = nil
      }
      return state.continuation
    }
    continuation?.resume(returning: value)
  }

  private func cancel(with value: Value) {
    let (continuation, cancelRequest) = state.withLock { state in
      state.isCancelled = true
      defer {
        state.continuation = nil
        state.cancelRequest = nil
      }
      return (state.continuation, state.cancelRequest)
    }
    cancelRequest?()
    continuation?.resume(returning: value)
  }
}
