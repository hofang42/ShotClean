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

  /// Capture dates before this are treated as unknown (e.g. an app layer that substitutes
  /// `.distantPast` for a missing `creationDate`, REV-4). Screenshots did not exist before.
  static let earliestPlausibleCaptureDate = Date(timeIntervalSince1970: 946_684_800)  // 2000-01-01

  public func classify(_ f: ScreenshotFeatures, now: Date) -> Verdict {
    // Fold once; every rule works on the same folded/tokenized text (BUG-6).
    let folded = TextNormalizer.fold(f.text)
    let text = TokenizedText(folded: folded)
    if isTransferReceipt(text, folded: folded) {
      return Verdict(
        category: .transferReceipt, suggestion: .keep, reason: "Biên lai chuyển khoản — luôn giữ")
    }
    // An unknown capture date must never make a screenshot look old (REV-4): age-based
    // fallbacks are skipped and year-less dates are read relative to `now`.
    let capturedAt: Date? = f.createdAt >= Self.earliestPlausibleCaptureDate ? f.createdAt : nil
    // Year-less dates are interpreted relative to when the screenshot was taken.
    var cachedDates: [Date]?
    let dates = { () -> [Date] in
      if let cachedDates { return cachedDates }
      let found =
        folded.isEmpty
        ? []
        : DateExtractor.dates(inFolded: folded, reference: capturedAt ?? now, calendar: calendar)
      cachedDates = found
      return found
    }
    if isTicket(text), let verdict = expiredTicket(capturedAt, dates: dates(), now: now) {
      return verdict
    }
    if isOrder(text), let verdict = expiredOrder(capturedAt, dates: dates(), now: now) {
      return verdict
    }
    if let capturedAt, let verdict = qrCode(f, capturedAt: capturedAt, now: now) {
      return verdict
    }
    return .other
  }

  // MARK: - Rules

  private var calendar: Calendar { thresholds.calendar }

  /// An amount AND one of:
  /// - a success phrase;
  /// - a bank/wallet name (ambiguous names such as "cake" or "MB" included) AND a field that
  ///   only exists on receipts (`ma giao dich`, `tai khoan nhan`, `so tai khoan`, …);
  /// - an unambiguous bank/wallet name AND ≥ 2 generic fields (`so tien`, `noi dung`,
  ///   `nguoi nhan`) AND no order-screen signal (BUG-1: "Người nhận" is a shipping label too).
  func isTransferReceipt(_ text: TokenizedText, folded: String) -> Bool {
    let looksLikeTransfer: Bool
    if text.containsAny(Keywords.transferSuccess) {
      looksLikeTransfer = true
    } else if text.containsAny(Keywords.strongTransferFields) {
      looksLikeTransfer =
        text.containsAny(Keywords.banksAndWallets) || text.containsAny(Keywords.ambiguousBanks)
    } else {
      looksLikeTransfer =
        text.containsAny(Keywords.banksAndWallets)
        && text.count(of: Keywords.weakTransferFields) >= 2
        && !isOrder(text)
    }
    return looksLikeTransfer && Self.containsAmount(folded)
  }

  /// A ticket-specific label, or two different generic travel words (BUG-4).
  func isTicket(_ text: TokenizedText) -> Bool {
    text.containsAny(Keywords.ticketStrong) || text.count(of: Keywords.ticketWeak) >= 2
  }

  /// An order identifier label (`ma van don`, `chi tiet don hang`, …), a status label together
  /// with a shop/carrier, or "đơn hàng" written right next to a shop/carrier name. A brand or
  /// "đơn hàng" alone (news, chats, ads) is not an order screen (BUG-3).
  func isOrder(_ text: TokenizedText) -> Bool {
    if text.containsAny(Keywords.orderIdentifiers) { return true }
    let brands = Keywords.orderBrands.filter(text.contains)
    guard !brands.isEmpty else { return false }
    if text.containsAny(Keywords.orderStatus) { return true }
    return brands.contains { brand in
      text.containsSequence(brand, Self.donHang) || text.containsSequence(Self.donHang, brand)
    }
  }

  private static let donHang = Phrase("don hang")

  private func expiredTicket(_ capturedAt: Date?, dates: [Date], now: Date) -> Verdict? {
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
    guard let capturedAt, isOlderThanOrderMaxAge(capturedAt, now: now) else { return nil }
    return Verdict(
      category: .expiredTicket, suggestion: .delete,
      reason: "Vé chụp hơn \(thresholds.orderMaxAgeDays) ngày trước")
  }

  private func expiredOrder(_ capturedAt: Date?, dates: [Date], now: Date) -> Verdict? {
    let orderDate: Date
    if let latest = dates.last, isOlderThanOrderMaxAge(latest, now: now) {
      orderDate = latest
    } else if let capturedAt, isOlderThanOrderMaxAge(capturedAt, now: now) {
      orderDate = capturedAt
    } else {
      return nil
    }
    return Verdict(
      category: .expiredOrder, suggestion: .delete,
      reason:
        "Đơn hàng từ \(calendar.dayMonth(orderDate)) — đã quá \(thresholds.orderMaxAgeDays) ngày")
  }

  private func qrCode(_ f: ScreenshotFeatures, capturedAt: Date, now: Date) -> Verdict? {
    guard f.qrAreaRatio >= thresholds.qrMinArea else { return nil }
    let age = calendar.wholeDays(from: capturedAt, to: now)
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
  /// Compiled once (BUG-6). `NSRegularExpression` is immutable, thread-safe and `Sendable`.
  private static let amountRegex: NSRegularExpression? = try? NSRegularExpression(
    pattern: [
      #"\d{1,3}(?:[.,]\d{3})+\s?(?:vnd|dong|d|₫)(?![a-z])"#,
      #"₫\s?\d{1,3}(?:[.,]\d{3})+"#,
      #"so tien\W{0,5}\d"#,
    ].joined(separator: "|"))

  static func containsAmount(_ folded: String) -> Bool {
    guard let amountRegex else {
      assertionFailure("invalid amount pattern")
      return false
    }
    return amountRegex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded))
      != nil
  }
}
