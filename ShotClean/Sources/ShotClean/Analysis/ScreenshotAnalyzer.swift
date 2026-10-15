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
/// `ScreenshotAsset`, ids, `Data` and `AnalyzedScreenshot` (all Sendable) enter or leave it.
struct ScreenshotAnalyzer: Sendable {
  struct Output: Sendable {
    var analyzed: [AnalyzedScreenshot] = []
    /// Archived feature prints of `analyzed`, by id (stored in `FeaturePrintStore`, REV-10).
    var featurePrints: [String: Data] = [:]
    /// Assets whose image could not be loaded without network access (iCloud-only, risk R4).
    var unavailableIDs: [String] = []
    /// Assets not analyzed because the scan was cancelled.
    var skippedCount = 0
  }

  /// Long side, in pixels, of the image used for Vision (REV-15, risk R3).
  ///
  /// iPhone screenshots are about 1179×2556 px. At 1024 px the long side shrinks to ~40 %, so
  /// body text ends up ~8–10 px high: too small for `.accurate` OCR to keep Vietnamese
  /// diacritics, and missed dates change ticket/order verdicts. 2048 px keeps text at ~80 %
  /// of its size. Memory stays bounded: one ~945×2048 RGBA image is ~7.7 MB and at most
  /// `maxConcurrentTasks` (2) are decoded at a time. Re-check fixture recall in R3.
  static let analysisLongSide: CGFloat = 2048

  let maxConcurrentTasks: Int

  init(maxConcurrentTasks: Int = 2) {
    self.maxConcurrentTasks = max(1, maxConcurrentTasks)
  }

  /// Analyzes `assets` with bounded concurrency: one child task per stripe (asset i goes to
  /// stripe i % maxConcurrentTasks). Each child fetches its `PHAsset`s with one
  /// `fetchAssets(withLocalIdentifiers:)` call and keeps them to itself (REV-16). Cancellation
  /// stops after the current asset and returns what finished. `progress` receives the number
  /// of processed assets.
  @concurrent
  func analyze(
    _ assets: [ScreenshotAsset],
    progress: @escaping @Sendable (Int) async -> Void
  ) async -> Output {
    _ = Self.recognitionLanguages  // Logs the supported OCR languages once (risk R1).
    let clock = ContinuousClock()
    let started = clock.now
    let stripeCount = min(maxConcurrentTasks, assets.count)
    let processed = OSAllocatedUnfairLock(initialState: 0)

    let output = await withTaskGroup(of: [Outcome].self, returning: Output.self) { group in
      for stripe in 0..<stripeCount {
        let batch = Swift.stride(from: stripe, to: assets.count, by: stripeCount).map {
          assets[$0]
        }
        group.addTask {
          await Self.analyzeBatch(batch) {
            let done = processed.withLock { count in
              count += 1
              return count
            }
            await progress(done)
          }
        }
      }
      var output = Output()
      output.analyzed.reserveCapacity(assets.count)
      for await outcomes in group {
        for outcome in outcomes {
          switch outcome {
          case .analyzed(let entry, let print):
            output.analyzed.append(entry)
            if let print { output.featurePrints[entry.features.id] = print }
          case .unavailable(let id): output.unavailableIDs.append(id)
          case .skipped: output.skippedCount += 1
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
    case analyzed(AnalyzedScreenshot, featurePrint: Data?)
    case unavailable(String)
    case skipped
  }

  /// Runs inside one child task: the `PHAsset`s fetched here never leave it.
  private static func analyzeBatch(
    _ batch: [ScreenshotAsset],
    onProcessed: @Sendable () async -> Void
  ) async -> [Outcome] {
    let fetched = PHAsset.fetchAssets(withLocalIdentifiers: batch.map(\.id), options: nil)
    var phAssets: [String: PHAsset] = [:]
    phAssets.reserveCapacity(fetched.count)
    for index in 0..<fetched.count {
      let asset = fetched.object(at: index)
      phAssets[asset.localIdentifier] = asset
    }

    var outcomes: [Outcome] = []
    outcomes.reserveCapacity(batch.count)
    for asset in batch {
      if Task.isCancelled {
        outcomes.append(.skipped)
        continue
      }
      if let phAsset = phAssets[asset.id] {
        outcomes.append(await analyzeOne(asset, phAsset: phAsset))
      } else {
        outcomes.append(.unavailable(asset.id))
      }
      await onProcessed()
    }
    return outcomes
  }

  private static func analyzeOne(_ asset: ScreenshotAsset, phAsset: PHAsset) async -> Outcome {
    guard let image = await loadImage(for: phAsset) else {
      if Task.isCancelled { return .skipped }
      Log.analysis.debug("No local image for an asset")
      return .unavailable(asset.id)
    }
    let vision = runVision(on: image)
    let digest = await sha256(of: phAsset)
    if Task.isCancelled { return .skipped }
    let features = ScreenshotFeatures(
      id: asset.id,
      // REV-4: a missing date becomes the Core's "unknown" sentinel, never a fake old age.
      createdAt: asset.creationDate ?? CaptureDate.unknown,
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
        // REV-5 / NEW-1: a thumbnail-only analysis or a missing hash is retried later (24 h),
        // when the asset changes, or on a full rescan.
        degradedAt: (image.isDegraded || digest == nil) ? Date() : nil
      ),
      featurePrint: vision.featurePrint)
  }

  // MARK: Image loading

  private struct LoadedImage {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
    /// Loaded from a low-quality local thumbnail (risk R4); OCR is likely incomplete.
    let isDegraded: Bool
  }

  private struct RequestedImage: Sendable {
    let image: UIImage
    let isDegraded: Bool
  }

  private static func loadImage(for asset: PHAsset) async -> LoadedImage? {
    let targetSize = analysisSize(width: asset.pixelWidth, height: asset.pixelHeight)
    // Best local rendition first; fall back to whatever local thumbnail exists (risk R4).
    for mode in [PHImageRequestOptionsDeliveryMode.highQualityFormat, .fastFormat] {
      if Task.isCancelled { return nil }
      if let requested = await requestImage(for: asset, targetSize: targetSize, deliveryMode: mode),
        let cgImage = requested.image.cgImage
      {
        return LoadedImage(
          cgImage: cgImage,
          orientation: CGImagePropertyOrientation(requested.image.imageOrientation),
          isDegraded: mode != .highQualityFormat || requested.isDegraded)
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

  /// Resumes on the first callback (a second or degraded-only callback can never hang or
  /// double-resume) and cancels the PhotoKit request when the task is cancelled (REV-16).
  private static func requestImage(
    for asset: PHAsset,
    targetSize: CGSize,
    deliveryMode: PHImageRequestOptionsDeliveryMode
  ) async -> RequestedImage? {
    await PhotoRequest<RequestedImage?>().run(cancelledValue: nil) { finish in
      let options = PHImageRequestOptions()
      options.deliveryMode = deliveryMode
      options.resizeMode = .fast
      options.version = .current
      options.isNetworkAccessAllowed = false
      options.isSynchronous = false
      let requestID = PHImageManager.default().requestImage(
        for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
      ) { image, info in
        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
        finish(image.map { RequestedImage(image: $0, isDegraded: isDegraded) })
      }
      return { PHImageManager.default().cancelImageRequest(requestID) }
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
      // REV-12: pin the revision; `nearDupMaxDistance` is tuned for it and cached prints must
      // stay comparable across OS updates (a revision change bumps `AnalysisCache.formatVersion`).
      printRequest.revision = VNGenerateImageFeaturePrintRequestRevision2

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

  /// Streams the current rendition through SHA-256. `nil` when it is not on device.
  ///
  /// REV-3: `.fullSizePhoto` is the rendered image *with* edits and exists only for edited
  /// assets; `.photo` is the unedited original. Hashing `.photo` for an edited asset would make
  /// an edited copy "identical" to its original. Never fall back to an arbitrary resource.
  private static func sha256(of asset: PHAsset) async -> Digest? {
    let resources = PHAssetResource.assetResources(for: asset)
    let wanted: PHAssetResourceType = asset.hasAdjustments ? .fullSizePhoto : .photo
    guard let resource = resources.first(where: { $0.type == wanted }) else { return nil }

    let state = OSAllocatedUnfairLock(uncheckedState: HashState())
    return await PhotoRequest<Digest?>().run(cancelledValue: nil) { finish in
      let options = PHAssetResourceRequestOptions()
      options.isNetworkAccessAllowed = false
      let requestID = PHAssetResourceManager.default().requestData(
        for: resource, options: options,
        dataReceivedHandler: { chunk in
          state.withLockUnchecked { $0.update(chunk) }
        },
        completionHandler: { error in
          if let error {
            Log.analysis.debug(
              "Rendition not available locally: \(error.localizedDescription, privacy: .public)")
            finish(nil)
          } else {
            finish(state.withLockUnchecked { $0.finalize() })
          }
        })
      return { PHAssetResourceManager.default().cancelDataRequest(requestID) }
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
