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

/// Live PhotoKit metadata of an asset. Refreshed from the library on every classification and
/// never part of cache validity: favoriting or adding to an album does not change the image.
public struct MetadataFlags: Sendable, Codable, Equatable, Hashable {
  /// `PHAsset.isFavorite`.
  public var isFavorite: Bool
  /// `PHAsset.hasAdjustments` (edited in Photos).
  public var hasAdjustments: Bool
  /// `mediaSubtypes` contains `.photoScreenshot`. `false` means a camera / saved photo.
  public var isScreenshot: Bool
  /// The asset is in at least one user-created album.
  public var inUserAlbum: Bool

  public init(
    isFavorite: Bool = false,
    hasAdjustments: Bool = false,
    isScreenshot: Bool = false,
    inUserAlbum: Bool = false
  ) {
    self.isFavorite = isFavorite
    self.hasAdjustments = hasAdjustments
    self.isScreenshot = isScreenshot
    self.inUserAlbum = inUserAlbum
  }

  /// Favorites, album members and edited assets are never suggested for deletion.
  public var isProtected: Bool { isFavorite || inUserAlbum || hasAdjustments }

  private enum CodingKeys: String, CodingKey {
    case isFavorite, hasAdjustments, isScreenshot, inUserAlbum
  }

  // Tolerant decoding: a missing flag is `false`.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    hasAdjustments = try container.decodeIfPresent(Bool.self, forKey: .hasAdjustments) ?? false
    isScreenshot = try container.decodeIfPresent(Bool.self, forKey: .isScreenshot) ?? false
    inUserAlbum = try container.decodeIfPresent(Bool.self, forKey: .inUserAlbum) ?? false
  }
}

/// Everything the Core needs to know about one screenshot or photo. Produced by the app layer
/// (PhotoKit + Vision + CryptoKit); the Core never touches images directly.
public struct ScreenshotFeatures: Sendable, Codable, Equatable {
  /// `PHAsset.localIdentifier`.
  public let id: String
  public let createdAt: Date
  public let pixelSize: PixelSize
  /// File size in bytes, `nil` when unknown.
  public let fileSize: Int64?
  /// Raw OCR text (not normalized). Empty for camera photos (OCR is skipped for them).
  public let text: String
  /// Total QR code area divided by image area, `0...1`.
  public let qrAreaRatio: Double
  /// Hex SHA-256 of the original image data, `nil` when unavailable (e.g. iCloud-only).
  public let sha256: String?
  /// Live library metadata; the app overwrites it from the latest fetch before classifying.
  public var metadata: MetadataFlags
  /// Mean luma of a downscaled grayscale copy, `0...1`; `nil` when not measured (screenshots).
  public let meanLuma: Double?
  /// Variance of a 3×3 Laplacian over a ≤ 512 px grayscale copy (0–255 intensity scale);
  /// lower is blurrier. `nil` when not measured.
  public let sharpness: Double?
  /// Vision aesthetics `overallScore` (`-1...1`, iOS 18+); `nil` when unavailable.
  public let aestheticsScore: Double?
  /// Vision aesthetics `isUtility` (receipts, documents, whiteboards…; iOS 18+).
  public let isUtility: Bool?

  public init(
    id: String,
    createdAt: Date,
    pixelSize: PixelSize,
    fileSize: Int64? = nil,
    text: String = "",
    qrAreaRatio: Double = 0,
    sha256: String? = nil,
    metadata: MetadataFlags = MetadataFlags(),
    meanLuma: Double? = nil,
    sharpness: Double? = nil,
    aestheticsScore: Double? = nil,
    isUtility: Bool? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.pixelSize = pixelSize
    self.fileSize = fileSize
    self.text = text
    self.qrAreaRatio = qrAreaRatio
    self.sha256 = sha256
    self.metadata = metadata
    self.meanLuma = meanLuma
    self.sharpness = sharpness
    self.aestheticsScore = aestheticsScore
    self.isUtility = isUtility
  }

  private enum CodingKeys: String, CodingKey {
    case id, createdAt, pixelSize, fileSize, text, qrAreaRatio, sha256, metadata, meanLuma
    case sharpness, aestheticsScore, isUtility
  }

  // Tolerant decoding: fields added after v1.1 may be missing.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    pixelSize = try container.decode(PixelSize.self, forKey: .pixelSize)
    fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
    text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    qrAreaRatio = try container.decodeIfPresent(Double.self, forKey: .qrAreaRatio) ?? 0
    sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
    metadata =
      try container.decodeIfPresent(MetadataFlags.self, forKey: .metadata) ?? MetadataFlags()
    meanLuma = try container.decodeIfPresent(Double.self, forKey: .meanLuma)
    sharpness = try container.decodeIfPresent(Double.self, forKey: .sharpness)
    aestheticsScore = try container.decodeIfPresent(Double.self, forKey: .aestheticsScore)
    isUtility = try container.decodeIfPresent(Bool.self, forKey: .isUtility)
  }
}

/// Primary category of a screenshot or photo. Declaration order matches rule priority (highest
/// first), with `expiredTicket` and `expiredOrder` sharing the same priority level:
///
/// `transferReceipt` > `exactDuplicate` > `expiredTicket`/`expiredOrder` > `qrCode` > `burstShot`
/// > `lowQualityPhoto` > `oldScreenshot` > `utilityPhoto` > `nearDuplicate` > `other`.
///
/// `lowQualityPhoto`/`utilityPhoto` only apply to camera photos; `oldScreenshot`/`burstShot`
/// only to screenshots. Protected assets (favorite, in a user album, edited) are `.other` with
/// a `.keep` suggestion unless they are receipts.
public enum Category: String, Sendable, Codable, CaseIterable {
  case transferReceipt, exactDuplicate, expiredTicket, expiredOrder, qrCode, burstShot
  case lowQualityPhoto, oldScreenshot, utilityPhoto, nearDuplicate, other
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

/// A group of exact duplicates, near duplicates or a burst of screenshots.
public struct Cluster: Sendable, Equatable {
  public enum Kind: String, Sendable {
    case exact, near, burst
  }

  public let kind: Kind
  /// Sorted by `createdAt` ascending (ties broken by id).
  public let memberIDs: [String]
  /// exact: oldest member · near: largest pixel area, ties → oldest · burst: newest member.
  /// exact / near: a protected member (favorite, album, edited) is preferred.
  public let keeperID: String

  public init(kind: Kind, memberIDs: [String], keeperID: String) {
    self.kind = kind
    self.memberIDs = memberIDs
    self.keeperID = keeperID
  }
}
