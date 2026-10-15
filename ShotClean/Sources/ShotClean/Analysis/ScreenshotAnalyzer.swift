import CryptoKit
import Foundation
import OSLog
import Photos
import ShotCleanCore
import UIKit
import Vision
import os  // OSAllocatedUnfairLock

/// Turns screenshots into `ScreenshotFeatures` (OCR, QR area, feature print, SHA-256), on device.
///
/// Every PhotoKit / Vision object is created and consumed inside a single child task; only
/// `ScreenshotAsset` and `AnalyzedScreenshot` (both Sendable) enter or leave it.
struct ScreenshotAnalyzer: Sendable {
  struct Output: Sendable {
    var analyzed: [AnalyzedScreenshot] = []
    /// Assets whose image could not be loaded without network access (iCloud-only, risk R4).
    var unavailableIDs: [String] = []
    /// Assets not analyzed because the scan was cancelled.
    var skippedCount = 0
  }

  /// Long side, in pixels, of the image used for Vision (risk R3).
  static let analysisLongSide: CGFloat = 1024

  let maxConcurrentTasks: Int

  init(maxConcurrentTasks: Int = 2) {
    self.maxConcurrentTasks = max(1, maxConcurrentTasks)
  }

  /// Analyzes `assets` with bounded concurrency. Cancellation stops scheduling new work and
  /// returns what finished. `progress` receives the number of processed assets.
  @concurrent
  func analyze(
    _ assets: [ScreenshotAsset],
    progress: @escaping @Sendable (Int) async -> Void
  ) async -> Output {
    _ = Self.recognitionLanguages  // Logs the supported OCR languages once (risk R1).
    let clock = ContinuousClock()
    let started = clock.now
    let limit = maxConcurrentTasks

    let output = await withTaskGroup(of: Outcome.self, returning: Output.self) { group in
      var output = Output()
      output.analyzed.reserveCapacity(assets.count)
      var nextIndex = 0
      var processed = 0

      while nextIndex < min(limit, assets.count) {
        let asset = assets[nextIndex]
        group.addTask { await Self.analyzeOne(asset) }
        nextIndex += 1
      }
      while let outcome = await group.next() {
        switch outcome {
        case .analyzed(let entry): output.analyzed.append(entry)
        case .unavailable(let id): output.unavailableIDs.append(id)
        case .skipped: output.skippedCount += 1
        }
        processed += 1
        await progress(processed)
        if nextIndex < assets.count {
          if Task.isCancelled {
            output.skippedCount += assets.count - nextIndex
            nextIndex = assets.count
          } else {
            let asset = assets[nextIndex]
            group.addTask { await Self.analyzeOne(asset) }
            nextIndex += 1
          }
        }
      }
      return output
    }

    let elapsed = clock.now - started
    let seconds =
      Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    let perImage = output.analyzed.isEmpty ? 0 : seconds / Double(output.analyzed.count)
    Log.analysis.info(
      """
      Analyzed \(output.analyzed.count) of \(assets.count) in \(seconds, format: .fixed(precision: 1))s \
      (\(perImage, format: .fixed(precision: 3))s/image), unavailable \(output.unavailableIDs.count), \
      skipped \(output.skippedCount)
      """)
    return output
  }

  // MARK: Per asset

  private enum Outcome: Sendable {
    case analyzed(AnalyzedScreenshot)
    case unavailable(String)
    case skipped
  }

  private static func analyzeOne(_ asset: ScreenshotAsset) async -> Outcome {
    if Task.isCancelled { return .skipped }
    guard
      let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil).firstObject
    else { return .unavailable(asset.id) }
    guard let image = await loadImage(for: phAsset) else {
      Log.analysis.debug("No local image for an asset")
      return .unavailable(asset.id)
    }
    let vision = runVision(on: image)
    let digest = await sha256(of: phAsset)
    let features = ScreenshotFeatures(
      id: asset.id,
      createdAt: asset.creationDate ?? .distantPast,
      pixelSize: PixelSize(width: asset.pixelWidth, height: asset.pixelHeight),
      fileSize: digest?.byteCount,
      text: vision.text,
      qrAreaRatio: vision.qrAreaRatio,
      sha256: digest?.hex
    )
    return .analyzed(
      AnalyzedScreenshot(
        features: features,
        modificationDate: asset.modificationDate,
        featurePrint: vision.featurePrint
      ))
  }

  // MARK: Image loading

  private struct LoadedImage {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
  }

  private static func loadImage(for asset: PHAsset) async -> LoadedImage? {
    let targetSize = analysisSize(width: asset.pixelWidth, height: asset.pixelHeight)
    // Best local rendition first; fall back to whatever local thumbnail exists (risk R4).
    for mode in [PHImageRequestOptionsDeliveryMode.highQualityFormat, .fastFormat] {
      if let image = await requestImage(for: asset, targetSize: targetSize, deliveryMode: mode),
        let cgImage = image.cgImage
      {
        return LoadedImage(
          cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
      }
    }
    return nil
  }

  private static func analysisSize(width: Int, height: Int) -> CGSize {
    guard width > 0, height > 0 else {
      return CGSize(width: analysisLongSide, height: analysisLongSide)
    }
    let scale = min(1, analysisLongSide / CGFloat(max(width, height)))
    return CGSize(
      width: (CGFloat(width) * scale).rounded(), height: (CGFloat(height) * scale).rounded())
  }

  private static func requestImage(
    for asset: PHAsset,
    targetSize: CGSize,
    deliveryMode: PHImageRequestOptionsDeliveryMode
  ) async -> UIImage? {
    let options = PHImageRequestOptions()
    options.deliveryMode = deliveryMode
    options.resizeMode = .fast
    options.version = .current
    options.isNetworkAccessAllowed = false
    options.isSynchronous = false
    // Both modes call the handler once when asynchronous; resume on the first call anyway so a
    // second (or degraded-only) callback can never hang or double-resume the continuation.
    return await withCheckedContinuation { continuation in
      let resumed = OSAllocatedUnfairLock(initialState: false)
      PHImageManager.default().requestImage(
        for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
      ) { image, _ in
        let isFirst = resumed.withLock { alreadyResumed in
          defer { alreadyResumed = true }
          return !alreadyResumed
        }
        guard isFirst else { return }
        continuation.resume(returning: image)
      }
    }
  }

  // MARK: Vision

  private struct VisionOutput {
    var text = ""
    var qrAreaRatio = 0.0
    var featurePrint: Data?
  }

  /// OCR languages: Vietnamese first when the `.accurate` recognizer supports it, then en-US.
  static let recognitionLanguages: [String] = {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    let supported: [String]
    do {
      supported = try request.supportedRecognitionLanguages()
    } catch {
      Log.analysis.error(
        "supportedRecognitionLanguages failed: \(error.localizedDescription, privacy: .public)")
      supported = []
    }
    Log.analysis.notice(
      "OCR supported languages (accurate, rev \(request.revision)): \(supported.joined(separator: ", "), privacy: .public)"
    )
    // Apple has used non-standard Vietnamese identifiers (e.g. "vi-VT"), so match the prefix.
    let vietnamese = supported.first { $0 == "vi-VN" } ?? supported.first { $0.hasPrefix("vi") }
    let chosen = (vietnamese.map { [$0] } ?? []) + ["en-US"]
    Log.analysis.notice("OCR languages used: \(chosen.joined(separator: ", "), privacy: .public)")
    return chosen
  }()

  private static func runVision(on image: LoadedImage) -> VisionOutput {
    autoreleasepool {
      let handler = VNImageRequestHandler(
        cgImage: image.cgImage, orientation: image.orientation, options: [:])
      var output = VisionOutput()

      let textRequest = VNRecognizeTextRequest()
      textRequest.recognitionLevel = .accurate
      textRequest.recognitionLanguages = recognitionLanguages
      textRequest.usesLanguageCorrection = false

      let barcodeRequest = VNDetectBarcodesRequest()
      barcodeRequest.symbologies = [.qr]

      let printRequest = VNGenerateImageFeaturePrintRequest()

      // Separate perform calls so one failing request does not discard the others.
      if perform(textRequest, on: handler) {
        output.text = (textRequest.results ?? [])
          .compactMap { $0.topCandidates(1).first?.string }
          .joined(separator: "\n")
      }
      if perform(barcodeRequest, on: handler) {
        let area = (barcodeRequest.results ?? [])
          .filter { $0.symbology == .qr }
          .reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
        output.qrAreaRatio = min(max(area, 0), 1)
      }
      if perform(printRequest, on: handler), let observation = printRequest.results?.first {
        output.featurePrint = FeaturePrintIndex.archive(observation)
      }
      return output
    }
  }

  private static func perform(_ request: VNRequest, on handler: VNImageRequestHandler) -> Bool {
    do {
      try handler.perform([request])
      return true
    } catch {
      Log.analysis.error(
        "\(String(describing: type(of: request)), privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
      )
      return false
    }
  }

  // MARK: SHA-256

  private struct Digest: Sendable {
    let hex: String
    let byteCount: Int64
  }

  /// Streams the original resource through SHA-256. `nil` when the original is not on device.
  private static func sha256(of asset: PHAsset) async -> Digest? {
    let resources = PHAssetResource.assetResources(for: asset)
    guard
      let resource = resources.first(where: { $0.type == .photo })
        ?? resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first
    else { return nil }

    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = false
    let state = OSAllocatedUnfairLock(uncheckedState: HashState())
    return await withCheckedContinuation { continuation in
      PHAssetResourceManager.default().requestData(
        for: resource, options: options,
        dataReceivedHandler: { chunk in
          state.withLockUnchecked { $0.update(chunk) }
        },
        completionHandler: { error in
          if let error {
            Log.analysis.debug(
              "Original not available locally: \(error.localizedDescription, privacy: .public)")
            continuation.resume(returning: nil)
          } else {
            continuation.resume(returning: state.withLockUnchecked { $0.finalize() })
          }
        })
    }
  }

  private struct HashState {
    var hasher = SHA256()
    var byteCount: Int64 = 0

    mutating func update(_ data: Data) {
      hasher.update(data: data)
      byteCount += Int64(data.count)
    }

    func finalize() -> Digest {
      let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
      return Digest(hex: hex, byteCount: byteCount)
    }
  }
}

extension CGImagePropertyOrientation {
  fileprivate init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
