import Foundation
import Vision

/// Lazily loads and unarchives `VNFeaturePrintObservation`s and computes distances between them.
/// Prints are read through `load` only for ids the clusterer compares (REV-10).
///
/// Not Sendable: create and use it inside one task (it backs the synchronous `distance`
/// closure passed to `LibraryAnalyzer.analyze`).
final class FeaturePrintIndex {
  private let load: (String) -> Data?
  private var observations: [String: VNFeaturePrintObservation] = [:]
  private var undecodable: Set<String> = []

  /// `load` returns the archived print for an id (e.g. `FeaturePrintStore.read`), or `nil`.
  init(load: @escaping (String) -> Data?) {
    self.load = load
  }

  /// Distance between two screenshots, `nil` when either print is missing or incompatible
  /// (e.g. different Vision revisions after an OS update).
  func distance(_ first: String, _ second: String) -> Float? {
    guard let lhs = observation(for: first), let rhs = observation(for: second) else {
      return nil
    }
    var distance: Float = 0
    do {
      try lhs.computeDistance(&distance, to: rhs)
    } catch {
      return nil
    }
    return distance
  }

  private func observation(for id: String) -> VNFeaturePrintObservation? {
    if let cached = observations[id] { return cached }
    guard !undecodable.contains(id), let data = load(id) else {
      undecodable.insert(id)
      return nil
    }
    let decoded = try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: VNFeaturePrintObservation.self, from: data)
    guard let decoded else {
      undecodable.insert(id)
      return nil
    }
    observations[id] = decoded
    return decoded
  }

  /// Archives a feature print for storage in `FeaturePrintStore`.
  static func archive(_ observation: VNFeaturePrintObservation) -> Data? {
    try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
  }
}
