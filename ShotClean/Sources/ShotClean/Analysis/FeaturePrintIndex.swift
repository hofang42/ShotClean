import Foundation
import Vision

/// Lazily unarchives `VNFeaturePrintObservation`s and computes distances between them.
///
/// Not Sendable: create and use it inside one task (it backs the synchronous `distance`
/// closure passed to `LibraryAnalyzer.analyze`).
final class FeaturePrintIndex {
  private let archives: [String: Data]
  private var observations: [String: VNFeaturePrintObservation] = [:]
  private var undecodable: Set<String> = []

  init(archives: [String: Data]) {
    self.archives = archives
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
    guard !undecodable.contains(id), let data = archives[id] else { return nil }
    let decoded = try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: VNFeaturePrintObservation.self, from: data)
    guard let decoded else {
      undecodable.insert(id)
      return nil
    }
    observations[id] = decoded
    return decoded
  }

  /// Archives a feature print for storage in `AnalysisCache`.
  static func archive(_ observation: VNFeaturePrintObservation) -> Data? {
    try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
  }
}
