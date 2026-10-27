import Photos
import PhotosUI  // PHPhotoLibrary.presentLimitedLibraryPicker(from:) lives in PhotosUI.
import ShotCleanCore
import UIKit
import os  // OSAllocatedUnfairLock

/// Sendable snapshot of the `PHAsset` metadata the app needs. Only this (and plain ids) crosses
/// concurrency boundaries; `PHAsset` itself never does.
struct ScreenshotAsset: Sendable, Hashable {
  let id: String
  let creationDate: Date?
  let modificationDate: Date?
  let pixelWidth: Int
  let pixelHeight: Int
  /// `PHAsset.isFavorite` (live metadata, never part of cache validity).
  var isFavorite = false
  /// `PHAsset.hasAdjustments` (edited in Photos).
  var hasAdjustments = false
  /// `mediaSubtypes` contains `.photoScreenshot`; `false` for camera / saved photos.
  var isScreenshot = true
  /// The asset belongs to at least one user-created album.
  var inUserAlbum = false

  /// Live flags for the Core.
  var metadata: MetadataFlags {
    MetadataFlags(
      isFavorite: isFavorite, hasAdjustments: hasAdjustments, isScreenshot: isScreenshot,
      inUserAlbum: inUserAlbum)
  }
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

/// PhotoKit access: authorization, fetching screenshots (and camera photos), thumbnails and
/// deletion.
///
/// Static helpers are `nonisolated` and only exchange `String` ids / `ScreenshotAsset`, so they can
/// run off the main actor. Closures handed to PhotoKit are formed in nonisolated code on purpose:
/// PhotoKit may call them on background queues.
@MainActor
final class ScreenshotLibrary {
  /// `PHAsset`s by id, built in one batch per published result (REV-8). Only touched on the
  /// main actor once handed over; never sent anywhere else.
  private var assets: [String: PHAsset] = [:]
  /// Ids forgotten while a batched fetch was in flight; its results must not re-add them.
  private var forgottenDuringSync: Set<String> = []
  /// Cache keys per id, so one id's thumbnails can be dropped (NSCache cannot enumerate).
  private var thumbnailKeys: [String: Set<String>] = [:]
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

  /// All screenshots visible to the app, plus every other image when `includePhotos`, oldest
  /// first, with live metadata (favorite, edited, in a user album). Synchronous; call off the
  /// main actor.
  nonisolated static func fetchAssets(includePhotos: Bool) -> [ScreenshotAsset] {
    let result = PHAsset.fetchAssets(
      with: .image, options: fetchOptions(includePhotos: includePhotos))
    let albumIDs = userAlbumAssetIDs()
    let screenshotBit = PHAssetMediaSubtype.photoScreenshot
    var assets: [ScreenshotAsset] = []
    assets.reserveCapacity(result.count)
    for index in 0..<result.count {
      let asset = result.object(at: index)
      let id = asset.localIdentifier
      assets.append(
        ScreenshotAsset(
          id: id,
          creationDate: asset.creationDate,
          modificationDate: asset.modificationDate,
          pixelWidth: asset.pixelWidth,
          pixelHeight: asset.pixelHeight,
          isFavorite: asset.isFavorite,
          hasAdjustments: asset.hasAdjustments,
          isScreenshot: asset.mediaSubtypes.contains(screenshotBit),
          inUserAlbum: albumIDs.contains(id)
        ))
    }
    let albumCount = albumIDs.count
    Log.library.info(
      "Fetched \(assets.count) assets (photos: \(includePhotos)), \(albumCount) in albums")
    return assets
  }

  /// Ids of image assets in any user-created album (folders included), built once per fetch:
  /// one fetch per album, ids only.
  private nonisolated static func userAlbumAssetIDs() -> Set<String> {
    let albums = PHAssetCollection.fetchAssetCollections(
      with: .album, subtype: .albumRegular, options: nil)
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "mediaType == %ld", PHAssetMediaType.image.rawValue)
    var ids = Set<String>()
    for albumIndex in 0..<albums.count {
      let members = PHAsset.fetchAssets(in: albums.object(at: albumIndex), options: options)
      for index in 0..<members.count {
        ids.insert(members.object(at: index).localIdentifier)
      }
    }
    return ids
  }

  /// Number of assets `fetchAssets(includePhotos:)` would return (cheap; used to detect changes
  /// on foreground).
  nonisolated static func assetCount(includePhotos: Bool) -> Int {
    PHAsset.fetchAssets(with: .image, options: fetchOptions(includePhotos: includePhotos)).count
  }

  private nonisolated static func fetchOptions(includePhotos: Bool) -> PHFetchOptions {
    let options = PHFetchOptions()
    if !includePhotos {
      options.predicate = NSPredicate(
        format: "(mediaSubtypes & %ld) != 0", Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
    }
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    return options
  }

  // MARK: Thumbnails

  /// Thumbnail for `id`. `size` is in pixels (points × display scale). Local data only.
  /// Cached in memory; the PhotoKit request is cancelled when the calling task is (REV-8).
  func thumbnail(for id: String, size: CGSize) async -> UIImage? {
    let key = "\(id)|\(Int(size.width))x\(Int(size.height))"
    if let cached = thumbnails.object(forKey: key as NSString) { return cached }
    guard let asset = await asset(for: id) else { return nil }
    let image = await PhotoRequest<UIImage?>().run(cancelledValue: nil) { finish in
      Self.startThumbnailRequest(asset: asset, size: size, finish: finish)
    }
    if let image, !Task.isCancelled {
      let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
      thumbnails.setObject(image, forKey: key as NSString, cost: cost)
      thumbnailKeys[id, default: []].insert(key)
    }
    return image
  }

  /// Brings the id → `PHAsset` map in line with the published result: one batched fetch for
  /// the ids not mapped yet, off the main actor, and drops ids that disappeared (REV-8).
  func syncAssets(with ids: Set<String>) async {
    forget(Set(assets.keys).subtracting(ids))
    let missing = Array(ids.subtracting(assets.keys))
    guard !missing.isEmpty else { return }
    forgottenDuringSync = []
    let fetched = await Self.fetchAssetMap(missing)
    for (id, asset) in fetched where assets[id] == nil && !forgottenDuringSync.contains(id) {
      assets[id] = asset
    }
  }

  /// Drops mapped assets and cached thumbnails for `ids` (deleted, gone, or modified).
  func forget(_ ids: Set<String>) {
    guard !ids.isEmpty else { return }
    forgottenDuringSync.formUnion(ids)
    for id in ids {
      assets[id] = nil
      for key in thumbnailKeys.removeValue(forKey: id) ?? [] {
        thumbnails.removeObject(forKey: key as NSString)
      }
    }
  }

  /// Mapped asset, or one fetched off the main actor when a cell appears before the map is
  /// built. Never a synchronous fetch on the main actor.
  private func asset(for id: String) async -> PHAsset? {
    if let asset = assets[id] { return asset }
    let fetched = await Self.fetchAssetMap([id])
    guard let asset = fetched[id] else { return nil }
    if assets[id] == nil { assets[id] = asset }
    return assets[id]
  }

  /// One `fetchAssets(withLocalIdentifiers:)` for all `ids`, on the global executor. The map is
  /// built here and handed over with `sending`: nothing else references these `PHAsset`s, so
  /// the compiler can prove the transfer to the main actor is race-free.
  @concurrent
  private nonisolated static func fetchAssetMap(_ ids: [String]) async -> sending [String: PHAsset]
  {
    let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
    var map: [String: PHAsset] = [:]
    map.reserveCapacity(result.count)
    for index in 0..<result.count {
      let asset = result.object(at: index)
      map[asset.localIdentifier] = asset
    }
    return map
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

/// Remembers whether the photo library changed since the last fetch, so returning to the
/// foreground skips the full fetch (every asset plus every user album) when nothing changed.
/// Favoriting, editing or adding to an album are library changes too, so protection stays live.
final class LibraryChangeMonitor: NSObject, PHPhotoLibraryChangeObserver, Sendable {
  static let shared = LibraryChangeMonitor()

  private struct State: Sendable {
    var registered = false
    /// `true` until the first fetch: nothing is known yet.
    var dirty = true
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Registers the observer once. Call only with read access.
  func startIfNeeded() {
    let register = state.withLock { state -> Bool in
      guard !state.registered else { return false }
      state.registered = true
      return true
    }
    if register { PHPhotoLibrary.shared().register(self) }
  }

  func photoLibraryDidChange(_ changeInstance: PHChange) {
    state.withLock { $0.dirty = true }
  }

  /// Whether the library changed since the previous call; clears the flag.
  func consumeChange() -> Bool {
    state.withLock { state in
      defer { state.dirty = false }
      return state.dirty
    }
  }
}
