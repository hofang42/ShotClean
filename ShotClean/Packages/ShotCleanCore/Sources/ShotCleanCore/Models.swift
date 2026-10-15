import Foundation

/// Pixel dimensions of a screenshot.
public struct PixelSize: Sendable, Codable, Hashable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  /// Total number of pixels (`width * height`).
  public var area: Int { width * height }
}

/// Everything the Core needs to know about one screenshot. Produced by the app layer
/// (PhotoKit + Vision + CryptoKit); the Core never touches images directly.
public struct ScreenshotFeatures: Sendable, Codable, Equatable {
  /// `PHAsset.localIdentifier`.
  public let id: String
  public let createdAt: Date
  public let pixelSize: PixelSize
  /// File size in bytes, `nil` when unknown.
  public let fileSize: Int64?
  /// Raw OCR text (not normalized).
  public let text: String
  /// Total QR code area divided by image area, `0...1`.
  public let qrAreaRatio: Double
  /// Hex SHA-256 of the original image data, `nil` when unavailable (e.g. iCloud-only).
  public let sha256: String?

  public init(
    id: String,
    createdAt: Date,
    pixelSize: PixelSize,
    fileSize: Int64? = nil,
    text: String = "",
    qrAreaRatio: Double = 0,
    sha256: String? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.pixelSize = pixelSize
    self.fileSize = fileSize
    self.text = text
    self.qrAreaRatio = qrAreaRatio
    self.sha256 = sha256
  }
}

/// Primary category of a screenshot. Declaration order matches rule priority (highest first),
/// with `expiredTicket` and `expiredOrder` sharing the same priority level.
public enum Category: String, Sendable, Codable, CaseIterable {
  case transferReceipt, exactDuplicate, expiredTicket, expiredOrder, qrCode, nearDuplicate, other
}

/// Final decision for one screenshot.
public struct Verdict: Sendable, Equatable {
  public enum Suggestion: String, Sendable, Equatable {
    case delete, keep, review, none
  }

  public let category: Category
  public let suggestion: Suggestion
  /// Human readable reason, in Vietnamese.
  public let reason: String

  public init(category: Category, suggestion: Suggestion, reason: String) {
    self.category = category
    self.suggestion = suggestion
    self.reason = reason
  }

  /// Verdict for a screenshot that matched no rule.
  public static let other = Verdict(category: .other, suggestion: .none, reason: "")
}

/// A group of exact or near duplicate screenshots.
public struct Cluster: Sendable, Equatable {
  public enum Kind: String, Sendable {
    case exact, near
  }

  public let kind: Kind
  /// Sorted by `createdAt` ascending (ties broken by id).
  public let memberIDs: [String]
  /// exact: oldest member · near: largest pixel area, ties → oldest.
  public let keeperID: String

  public init(kind: Kind, memberIDs: [String], keeperID: String) {
    self.kind = kind
    self.memberIDs = memberIDs
    self.keeperID = keeperID
  }
}
