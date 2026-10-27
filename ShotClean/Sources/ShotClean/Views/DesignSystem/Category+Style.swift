import ShotCleanCore
import SwiftUI

typealias ShotCategory = ShotCleanCore.Category

/// Per-category presentation: Vietnamese title, SF Symbol and color (UI-SPEC §3).
/// Color is never the only signal; the symbol and title always accompany it.
extension ShotCategory {
  /// Order of the category cards on the overview (receipts are shown separately).
  static let cleanable: [ShotCategory] = [
    .exactDuplicate, .qrCode, .expiredTicket, .expiredOrder, .nearDuplicate,
  ]

  var title: String {
    switch self {
    case .exactDuplicate: Strings.Category.exact
    case .nearDuplicate: Strings.Category.near
    case .qrCode: Strings.Category.qr
    case .expiredTicket: Strings.Category.ticket
    case .expiredOrder: Strings.Category.order
    case .transferReceipt: Strings.Category.receipt
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
