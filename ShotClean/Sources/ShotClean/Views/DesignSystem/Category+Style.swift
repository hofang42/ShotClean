import ShotCleanCore
import SwiftUI

typealias ShotCategory = ShotCleanCore.Category

/// Per-category presentation: Vietnamese title, SF Symbol and color (UI-SPEC §3).
/// Color is never the only signal; the symbol and title always accompany it.
extension ShotCategory {
  /// Order of the category cards on the overview (receipts are shown separately).
  static let cleanable: [ShotCategory] = [
    .exactDuplicate, .burstShot, .oldScreenshot, .lowQualityPhoto, .qrCode, .expiredTicket,
    .expiredOrder, .nearDuplicate, .utilityPhoto,
  ]

  /// Categories that are only ever suggested for review, never preselected.
  static let reviewOnly: Set<ShotCategory> = [.nearDuplicate, .utilityPhoto]

  var title: String {
    switch self {
    case .exactDuplicate: Strings.Category.exact
    case .nearDuplicate: Strings.Category.near
    case .qrCode: Strings.Category.qr
    case .expiredTicket: Strings.Category.ticket
    case .expiredOrder: Strings.Category.order
    case .transferReceipt: Strings.Category.receipt
    case .burstShot: Strings.Category.burst
    case .oldScreenshot: Strings.Category.oldScreenshot
    case .lowQualityPhoto: Strings.Category.lowQuality
    case .utilityPhoto: Strings.Category.utility
    case .other: Strings.Category.other
    }
  }

  var shortTitle: String {
    switch self {
    case .exactDuplicate: Strings.Category.exactShort
    case .nearDuplicate: Strings.Category.nearShort
    case .qrCode: Strings.Category.qrShort
    case .expiredTicket: Strings.Category.ticketShort
    case .expiredOrder: Strings.Category.orderShort
    case .transferReceipt: Strings.Category.receiptShort
    case .burstShot: Strings.Category.burstShort
    case .oldScreenshot: Strings.Category.oldScreenshotShort
    case .lowQualityPhoto: Strings.Category.lowQualityShort
    case .utilityPhoto: Strings.Category.utilityShort
    case .other: Strings.Category.otherShort
    }
  }

  /// One-line explanation on the category card.
  var summary: String {
    switch self {
    case .exactDuplicate: Strings.Category.exactSummary
    case .nearDuplicate: Strings.Category.nearSummary
    case .qrCode: Strings.Category.qrSummary
    case .expiredTicket: Strings.Category.ticketSummary
    case .expiredOrder: Strings.Category.orderSummary
    case .transferReceipt: Strings.Category.receiptSummary
    case .burstShot: Strings.Category.burstSummary
    case .oldScreenshot: Strings.Category.oldScreenshotSummary
    case .lowQualityPhoto: Strings.Category.lowQualitySummary
    case .utilityPhoto: Strings.Category.utilitySummary
    case .other: Strings.Category.otherSummary
    }
  }

  var symbolName: String {
    switch self {
    case .exactDuplicate: "doc.on.doc"
    case .nearDuplicate: "square.on.square.dashed"
    case .qrCode: "qrcode"
    case .expiredTicket: "ticket"
    case .expiredOrder: "shippingbox"
    case .transferReceipt: "checkmark.shield"
    case .burstShot: "square.stack.3d.down.right"
    case .oldScreenshot: "clock.arrow.circlepath"
    case .lowQualityPhoto: "camera.aperture"
    case .utilityPhoto: "doc.text.viewfinder"
    case .other: "photo"
    }
  }

  var tint: Color {
    switch self {
    case .exactDuplicate: Color(light: 0x4F5BE8, dark: 0x8B93FF)
    case .nearDuplicate: Color(light: 0x0E9F9A, dark: 0x2CD1C8)
    case .qrCode: Color(light: 0x8E44EC, dark: 0xB07CFF)
    case .expiredTicket: Color(light: 0xF27A1A, dark: 0xFF9A45)
    case .expiredOrder: Color(light: 0xD9A100, dark: 0xF2C230)
    case .transferReceipt: Theme.keep
    case .burstShot: Color(light: 0x2F7DE1, dark: 0x5EA2FF)
    case .oldScreenshot: Color(light: 0x7A6A58, dark: 0xB8A48C)
    case .lowQualityPhoto: Color(light: 0xD6455D, dark: 0xFF6F86)
    case .utilityPhoto: Color(light: 0x5B6B7F, dark: 0x9AAABD)
    case .other: Color.gray
    }
  }
}

extension Verdict.Suggestion {
  var title: String {
    switch self {
    case .delete: Strings.Suggestion.delete
    case .keep: Strings.Suggestion.keep
    case .review: Strings.Suggestion.review
    case .none: Strings.Suggestion.none
    }
  }
}

extension Cluster.Kind {
  /// Category whose style (title, symbol, tint) represents this kind of cluster.
  var category: ShotCategory {
    switch self {
    case .exact: .exactDuplicate
    case .near: .nearDuplicate
    case .burst: .burstShot
    }
  }

  /// Short title used in each cluster row header.
  var rowTitle: String {
    switch self {
    case .exact: Strings.Cluster.exactTitle
    case .near: Strings.Cluster.nearTitle
    case .burst: Strings.Cluster.burstTitle
    }
  }

  /// Explanation shown above the clusters.
  var intro: String {
    switch self {
    case .exact: Strings.Cluster.exactIntro
    case .near: Strings.Cluster.nearIntro
    case .burst: Strings.Cluster.burstIntro
    }
  }

  /// How the Core picks the keeper (REV-19): exact → oldest, near → largest, burst → newest.
  var coreKeeperNote: String {
    switch self {
    case .exact: Strings.Cluster.keeperOldest
    case .near: Strings.Cluster.keeperLargest
    case .burst: Strings.Cluster.keeperNewest
    }
  }
}
