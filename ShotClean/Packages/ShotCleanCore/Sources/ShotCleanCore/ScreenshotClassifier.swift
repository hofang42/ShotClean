import Foundation

/// Classifies a single screenshot by its own content (receipt, ticket, order, QR).
/// Duplicate detection needs the whole library and lives in `DuplicateClusterer` /
/// `LibraryAnalyzer`, so this never returns `.exactDuplicate` or `.nearDuplicate`.
///
/// Priority: `transferReceipt` > `expiredTicket` > `expiredOrder` > `qrCode` > `other`.
public struct ScreenshotClassifier: Sendable {
  public let thresholds: Thresholds

  public init(thresholds: Thresholds = .default) {
    self.thresholds = thresholds
  }

  public func classify(_ f: ScreenshotFeatures, now: Date) -> Verdict {
    let folded = TextNormalizer.fold(f.text)
    if isTransferReceipt(folded) {
      return Verdict(
        category: .transferReceipt, suggestion: .keep, reason: "Biên lai chuyển khoản — luôn giữ")
    }
    // Year-less dates are interpreted relative to when the screenshot was taken.
    let dates =
      folded.isEmpty
      ? [] : DateExtractor.dates(in: f.text, reference: f.createdAt, calendar: calendar)
    if let verdict = expiredTicket(f, folded: folded, dates: dates, now: now) {
      return verdict
    }
    if let verdict = expiredOrder(f, folded: folded, dates: dates, now: now) {
      return verdict
    }
    if let verdict = qrCode(f, now: now) {
      return verdict
    }
    return .other
  }

  // MARK: - Rules

  private var calendar: Calendar { thresholds.calendar }

  /// (success phrase OR (bank/wallet AND receipt field)) AND an amount.
  func isTransferReceipt(_ folded: String) -> Bool {
    let looksLikeTransfer =
      Keywords.containsAny(Keywords.transferSuccess, in: folded)
      || (Keywords.containsAny(Keywords.banksAndWallets, in: folded)
        && Keywords.containsAny(Keywords.transferFields, in: folded))
    return looksLikeTransfer && Self.containsAmount(folded)
  }

  private func expiredTicket(
    _ f: ScreenshotFeatures, folded: String, dates: [Date], now: Date
  ) -> Verdict? {
    guard Keywords.containsAny(Keywords.ticket, in: folded) else { return nil }
    if let latest = dates.last {
      // Expired when the latest date is before (today − grace).
      let today = calendar.startOfDay(for: now)
      guard
        let cutoff = calendar.date(byAdding: .day, value: -thresholds.ticketGraceDays, to: today),
        latest < cutoff
      else { return nil }
      return Verdict(
        category: .expiredTicket, suggestion: .delete,
        reason: "Vé ngày \(calendar.dayMonthYear(latest)) đã qua")
    }
    guard isOlderThanOrderMaxAge(f.createdAt, now: now) else { return nil }
    return Verdict(
      category: .expiredTicket, suggestion: .delete,
      reason: "Vé chụp hơn \(thresholds.orderMaxAgeDays) ngày trước")
  }

  private func expiredOrder(
    _ f: ScreenshotFeatures, folded: String, dates: [Date], now: Date
  ) -> Verdict? {
    guard Keywords.containsAny(Keywords.order, in: folded) else { return nil }
    let orderDate: Date
    if let latest = dates.last, isOlderThanOrderMaxAge(latest, now: now) {
      orderDate = latest
    } else if isOlderThanOrderMaxAge(f.createdAt, now: now) {
      orderDate = f.createdAt
    } else {
      return nil
    }
    return Verdict(
      category: .expiredOrder, suggestion: .delete,
      reason:
        "Đơn hàng từ \(calendar.dayMonth(orderDate)) — đã quá \(thresholds.orderMaxAgeDays) ngày")
  }

  private func qrCode(_ f: ScreenshotFeatures, now: Date) -> Verdict? {
    guard f.qrAreaRatio >= thresholds.qrMinArea else { return nil }
    let age = calendar.wholeDays(from: f.createdAt, to: now)
    guard age >= thresholds.qrMinAgeDays else { return nil }
    return Verdict(category: .qrCode, suggestion: .delete, reason: "Mã QR, chụp \(age) ngày trước")
  }

  private func isOlderThanOrderMaxAge(_ date: Date, now: Date) -> Bool {
    guard let cutoff = calendar.date(byAdding: .day, value: -thresholds.orderMaxAgeDays, to: now)
    else { return false }
    return date < cutoff
  }

  // MARK: - Amount detection

  /// Amount patterns on folded text:
  /// `1.250.000 vnd`, `500,000 d`, `150.000d`, `₫259.000`, or `so tien` followed by digits.
  private static let amountPatterns = [
    #"\d{1,3}(?:[.,]\d{3})+\s?(?:vnd|dong|d|₫)(?![a-z])"#,
    #"₫\s?\d{1,3}(?:[.,]\d{3})+"#,
    #"so tien\W{0,5}\d"#,
  ]

  static func containsAmount(_ folded: String) -> Bool {
    let range = NSRange(folded.startIndex..., in: folded)
    return amountPatterns.contains { pattern in
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
      return regex.firstMatch(in: folded, range: range) != nil
    }
  }
}
