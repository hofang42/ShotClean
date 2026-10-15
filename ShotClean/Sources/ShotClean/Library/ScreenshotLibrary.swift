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
  /// `PHAsset`s by id, so grid cells do not hit the photo database once per cell (REV-8).
  /// Only touched on the main actor; never sent to another isolation domain.
  private var assets: [String: PHAsset] = [:]
  /// Decoded thumbnails keyed by id and pixel size.
  private let thumbnails: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.totalCostLimit = 64 * 1024 * 1024
    return cache
  }()

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
    let result = PHAsset.fetchAssets(with: .image, options: screenshotFetchOptions())
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

  /// Number of screenshots visible to the app (cheap; used to detect changes on foreground).
  nonisolated static func screenshotCount() -> Int {
    PHAsset.fetchAssets(with: .image, options: screenshotFetchOptions()).count
  }

  private nonisolated static func screenshotFetchOptions() -> PHFetchOptions {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(
      format: "(mediaSubtypes & %ld) != 0", Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    return options
  }

  // MARK: Thumbnails

  /// Thumbnail for `id`. `size` is in pixels (points × display scale). Local data only.
  /// Cached in memory; the PhotoKit request is cancelled when the calling task is (REV-8).
  func thumbnail(for id: String, size: CGSize) async -> UIImage? {
    let key = "\(id)|\(Int(size.width))x\(Int(size.height))" as NSString
    if let cached = thumbnails.object(forKey: key) { return cached }
    guard let asset = asset(for: id) else { return nil }
    let image = await PhotoRequest<UIImage?>().run(cancelledValue: nil) { finish in
      Self.startThumbnailRequest(asset: asset, size: size, finish: finish)
    }
    if let image, !Task.isCancelled {
      let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
      thumbnails.setObject(image, forKey: key, cost: cost)
    }
    return image
  }

  /// Forgets cached assets and thumbnails (after deletion or a rescan).
  func forget(_ ids: Set<String>? = nil) {
    guard let ids else {
      assets.removeAll()
      thumbnails.removeAllObjects()
      return
    }
    for id in ids { assets[id] = nil }
    // NSCache cannot enumerate keys; deleted ids are never requested again, so a full flush is
    // only needed when an asset might have changed (rescan).
  }

  private func asset(for id: String) -> PHAsset? {
    if let asset = assets[id] { return asset }
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    else { return nil }
    assets[id] = asset
    return asset
  }

  /// Formed in nonisolated code: PhotoKit calls the handler on its own queue.
  private nonisolated static func startThumbnailRequest(
    asset: PHAsset,
    size: CGSize,
    finish: @escaping @Sendable (UIImage?) -> Void
  ) -> @Sendable () -> Void {
    let options = PHImageRequestOptions()
    // `.highQualityFormat` + asynchronous → the handler is called once (extra calls are ignored).
    options.deliveryMode = .highQualityFormat
    options.resizeMode = .fast
    options.isNetworkAccessAllowed = false
    options.isSynchronous = false
    let requestID = PHImageManager.default().requestImage(
      for: asset, targetSize: size, contentMode: .aspectFill, options: options
    ) { image, _ in
      finish(image)
    }
    return { PHImageManager.default().cancelImageRequest(requestID) }
  }

  // MARK: Deletion

  /// Deletes the assets with `ids` in one `PHAssetChangeRequest` batch. iOS shows its own
  /// confirmation dialog for the whole batch.
  nonisolated static func deleteAssets(withIDs ids: [String]) async throws -> DeleteResult {
    guard !ids.isEmpty else { return .nothingToDelete }
    let count = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count
    guard count > 0 else {
      Log.library.info("None of \(ids.count) assets exist any more")
      return .nothingToDelete
    }
    do {
      try await PHPhotoLibrary.shared().performChanges {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        PHAssetChangeRequest.deleteAssets(assets)
      }
    } catch let error as PHPhotosError where error.code == .userCancelled {
      Log.library.info("User cancelled deletion of \(count) assets")
      return .cancelled
    }
    Log.library.info("Deleted \(count) assets")
    return .deleted(count)
  }
}
