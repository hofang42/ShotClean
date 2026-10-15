import Photos
import PhotosUI  // PHPhotoLibrary.presentLimitedLibraryPicker(from:) lives in PhotosUI.
import UIKit

/// Sendable snapshot of the `PHAsset` metadata the app needs. Only this (and plain ids) crosses
/// concurrency boundaries; `PHAsset` itself never does.
struct ScreenshotAsset: Sendable, Hashable {
  let id: String
  let creationDate: Date?
  let modificationDate: Date?
  let pixelWidth: Int
  let pixelHeight: Int
}

/// Photo library access level, mapped from `PHAuthorizationStatus` (`.readWrite`).
enum PhotoAccess: Sendable, Equatable {
  case notDetermined, authorized, limited, denied

  init(_ status: PHAuthorizationStatus) {
    switch status {
    case .notDetermined: self = .notDetermined
    case .authorized: self = .authorized
    case .limited: self = .limited
    case .denied, .restricted: self = .denied
    @unknown default: self = .denied
    }
  }

  var canRead: Bool { self == .authorized || self == .limited }
}

/// PhotoKit access: authorization, fetching screenshots, thumbnails and deletion.
///
/// Static helpers are `nonisolated` and only exchange `String` ids / `ScreenshotAsset`, so they can
/// run off the main actor. Closures handed to PhotoKit are formed in nonisolated code on purpose:
/// PhotoKit may call them on background queues.
@MainActor
final class ScreenshotLibrary {
  private let imageManager = PHCachingImageManager()

  // MARK: Authorization

  nonisolated static func currentAccess() -> PhotoAccess {
    PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
  }

  nonisolated static func requestAccess() async -> PhotoAccess {
    PhotoAccess(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
  }

  /// Shows the system picker to extend a limited selection. Returns when the picker is dismissed.
  func presentLimitedLibraryPicker() async {
    guard let presenter = Self.topViewController() else {
      Log.library.error("No view controller to present the limited library picker")
      return
    }
    let ids = await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
    Log.library.info("Limited picker returned \(ids.count) newly selected assets")
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  // MARK: Fetching

  /// All screenshots visible to the app, oldest first. Synchronous; call off the main actor.
  nonisolated static func fetchScreenshots() -> [ScreenshotAsset] {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(
      format: "(mediaSubtypes & %ld) != 0", Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    let result = PHAsset.fetchAssets(with: .image, options: options)
    var assets: [ScreenshotAsset] = []
    assets.reserveCapacity(result.count)
    for index in 0..<result.count {
      let asset = result.object(at: index)
      assets.append(
        ScreenshotAsset(
          id: asset.localIdentifier,
          creationDate: asset.creationDate,
          modificationDate: asset.modificationDate,
          pixelWidth: asset.pixelWidth,
          pixelHeight: asset.pixelHeight
        ))
    }
    Log.library.info("Fetched \(assets.count) screenshots")
    return assets
  }

  // MARK: Thumbnails

  /// Thumbnail for `id`. `size` is in pixels (points × display scale). Local data only.
  func thumbnail(for id: String, size: CGSize) async -> UIImage? {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    else { return nil }
    let manager = imageManager
    return await withCheckedContinuation { continuation in
      Self.requestThumbnail(
        manager: manager, asset: asset, size: size, continuation: continuation)
    }
  }

  private nonisolated static func requestThumbnail(
    manager: PHCachingImageManager,
    asset: PHAsset,
    size: CGSize,
    continuation: CheckedContinuation<UIImage?, Never>
  ) {
    let options = PHImageRequestOptions()
    // `.highQualityFormat` + asynchronous → the handler is called exactly once.
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .fast
    options.isNetworkAccessAllowed = false
    options.isSynchronous = false
    manager.requestImage(
      for: asset, targetSize: size, contentMode: .aspectFill, options: options
    ) { image, _ in
      continuation.resume(returning: image)
    }
  }

  // MARK: Deletion

  /// Deletes the assets with `ids`. iOS shows its own confirmation dialog for the whole batch.
  /// - Returns: number of assets deleted; `0` when the user cancels the system dialog.
  nonisolated static func deleteAssets(withIDs ids: [String]) async throws -> Int {
    guard !ids.isEmpty else { return 0 }
    let count = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count
    guard count > 0 else { return 0 }
    do {
      try await PHPhotoLibrary.shared().performChanges {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        PHAssetChangeRequest.deleteAssets(assets)
      }
    } catch let error as PHPhotosError where error.code == .userCancelled {
      Log.library.info("User cancelled deletion of \(count) assets")
      return 0
    }
    Log.library.info("Deleted \(count) assets")
    return count
  }
}
