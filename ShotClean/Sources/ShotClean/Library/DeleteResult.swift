/// Outcome of a deletion request (REV-17).
enum DeleteResult: Sendable, Equatable {
  /// The user confirmed the iOS dialog; `count` assets moved to "Recently Deleted".
  case deleted(Int)
  /// The user cancelled the iOS confirmation dialog.
  case cancelled
  /// None of the requested assets exist any more; no dialog was shown.
  case nothingToDelete
}
