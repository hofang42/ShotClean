import Foundation
import Testing

@testable import ShotCleanCore

@Suite("ScreenshotClassifier")
struct ScreenshotClassifierTests {
  let classifier = ScreenshotClassifier(thresholds: TestSupport.thresholds)
  let now = TestSupport.now

  func classify(_ text: String, createdAt: Date = TestSupport.daysAgo(1), qr: Double = 0)
    -> Verdict
  {
    classifier.classify(
      TestSupport.features("x", createdAt: createdAt, text: text, qr: qr), now: now)
  }

  // MARK: transferReceipt

  @Test(
    "bank / wallet transfer receipts are always kept",
    arguments: [
      OCRSample.vietcombankTransfer,
      OCRSample.mbBankTransfer,
      OCRSample.techcombankTransfer,
      OCRSample.momoTransfer,
    ])
  func receipts(text: String) {
    let verdict = classify(text, createdAt: TestSupport.daysAgo(400))
    #expect(verdict.category == .transferReceipt)
    #expect(verdict.suggestion == .keep)
    #expect(verdict.reason == "Biên lai chuyển khoản — luôn giữ")
  }

  @Test("success phrase without an amount is not a receipt")
  func successPhraseWithoutAmount() {
    #expect(classify("Chuyển tiền thành công\nCảm ơn quý khách").category == .other)
  }

  @Test("bank name and amount without a transfer field is not a receipt")
  func bankPromoIsNotReceipt() {
    #expect(classify(OCRSample.bankPromo).category == .other)
  }

  @Test("'so tien' followed by plain digits counts as an amount")
  func soTienAmount() {
    #expect(classify("Giao dịch thành công\nSố tiền: 75000").category == .transferReceipt)
  }

  // MARK: expiredTicket

  @Test("past boarding pass is suggested for deletion with its date")
  func expiredBoardingPass() {
    let verdict = classify(OCRSample.vietjetBoardingPass, createdAt: TestSupport.date(2026, 9, 1))
    #expect(
      verdict
        == Verdict(
          category: .expiredTicket, suggestion: .delete, reason: "Vé ngày 12/09/2026 đã qua"))
  }

  @Test("past bus ticket is suggested for deletion")
  func expiredBusTicket() {
    let verdict = classify(OCRSample.busTicket, createdAt: TestSupport.date(2026, 9, 28))
    #expect(
      verdict
        == Verdict(
          category: .expiredTicket, suggestion: .delete, reason: "Vé ngày 01/10/2026 đã qua"))
  }

  @Test("future boarding pass is not deleted")
  func futureTicket() {
    #expect(classify(OCRSample.vietnamAirlinesFutureBoardingPass).category == .other)
  }

  @Test("ticket within the grace period is not deleted")
  func ticketGracePeriod() {
    // now = 15/10; grace 1 day → a ticket dated 14/10 is still kept, 13/10 is expired.
    #expect(classify("Vé xe 14/10/2026", createdAt: TestSupport.daysAgo(3)).category == .other)
    #expect(
      classify("Vé xe 13/10/2026", createdAt: TestSupport.daysAgo(3)).category == .expiredTicket)
  }

  @Test("ticket uses the latest date in the text")
  func ticketLatestDate() {
    let text = "Vé tàu SE1\nĐặt ngày 01/10/2026\nKhởi hành 20/10/2026"
    #expect(classify(text, createdAt: TestSupport.daysAgo(10)).category == .other)
  }

  @Test("ticket without date is deleted only when the screenshot is older than 30 days")
  func ticketWithoutDate() {
    let text = "Boarding pass\nFlight VJ123\nGate 5"
    #expect(
      classify(text, createdAt: TestSupport.daysAgo(40))
        == Verdict(
          category: .expiredTicket, suggestion: .delete, reason: "Vé chụp hơn 30 ngày trước"))
    #expect(classify(text, createdAt: TestSupport.daysAgo(5)).category == .other)
  }

  @Test("a past date without ticket keywords is not a ticket")
  func chatWithDateIsNotTicket() {
    // "Về" folds to "ve" and must not be treated as "vé".
    #expect(classify(OCRSample.randomChat, createdAt: TestSupport.daysAgo(60)).category == .other)
  }

  // MARK: expiredOrder

  @Test("order delivered more than 30 days ago is deleted with the order date")
  func expiredShopeeOrder() {
    let verdict = classify(
      OCRSample.shopeeDeliveredOrder, createdAt: TestSupport.date(2026, 8, 16))
    #expect(
      verdict
        == Verdict(
          category: .expiredOrder, suggestion: .delete, reason: "Đơn hàng từ 15/08 — đã quá 30 ngày"
        ))
  }

  @Test("recent screenshot with an old delivery date in text is expired")
  func expiredOrderByTextDate() {
    let verdict = classify("Shopee\nĐã giao 01/09/2026", createdAt: TestSupport.daysAgo(1))
    #expect(verdict.category == .expiredOrder)
    #expect(verdict.reason == "Đơn hàng từ 01/09 — đã quá 30 ngày")
  }

  @Test("old order screenshot without a text date uses the capture date")
  func expiredOrderByCaptureDate() {
    let verdict = classify("Lazada\nĐang vận chuyển", createdAt: TestSupport.date(2026, 9, 1, 15))
    #expect(
      verdict
        == Verdict(
          category: .expiredOrder, suggestion: .delete, reason: "Đơn hàng từ 01/09 — đã quá 30 ngày"
        ))
  }

  @Test("recent order is not deleted")
  func recentOrder() {
    #expect(
      classify(OCRSample.ghnTracking, createdAt: TestSupport.date(2026, 9, 20)).category == .other)
  }

  // MARK: qrCode

  @Test("QR screenshot older than 7 days is deleted")
  func qrOld() {
    #expect(
      classify("", createdAt: TestSupport.daysAgo(10), qr: 0.4)
        == Verdict(category: .qrCode, suggestion: .delete, reason: "Mã QR, chụp 10 ngày trước"))
  }

  @Test("recent QR is not deleted", arguments: [0.5, 6.9])
  func qrRecent(days: Double) {
    #expect(classify("", createdAt: TestSupport.daysAgo(days), qr: 0.4).category == .other)
  }

  @Test("QR area must reach the minimum ratio")
  func qrArea() {
    #expect(classify("", createdAt: TestSupport.daysAgo(30), qr: 0.149).category == .other)
    #expect(classify("", createdAt: TestSupport.daysAgo(30), qr: 0.15).category == .qrCode)
  }

  // MARK: priority

  @Test("receipt with a large QR is still kept")
  func receiptBeatsQR() {
    let verdict = classify(
      OCRSample.vietcombankTransfer, createdAt: TestSupport.daysAgo(30), qr: 0.3)
    #expect(verdict.category == .transferReceipt)
    #expect(verdict.suggestion == .keep)
  }

  @Test("paid flight receipt beats expired ticket")
  func receiptBeatsTicket() {
    #expect(
      classify(OCRSample.flightPaymentReceipt, createdAt: TestSupport.daysAgo(40)).category
        == .transferReceipt)
  }

  @Test("expired ticket with a QR is categorized as ticket")
  func ticketBeatsQR() {
    let verdict = classify(
      OCRSample.vietjetBoardingPass, createdAt: TestSupport.date(2026, 9, 1), qr: 0.25)
    #expect(verdict.category == .expiredTicket)
  }

  @Test("old order with a QR is categorized as order")
  func orderBeatsQR() {
    let verdict = classify("GHTK\nMã vận đơn S123", createdAt: TestSupport.daysAgo(45), qr: 0.3)
    #expect(verdict.category == .expiredOrder)
  }

  // MARK: rule tightening (BUG-1..4)

  @Test("bank + two generic receipt fields + amount, no success phrase, is still a receipt")
  func receiptWithGenericFieldsOnly() {
    let text = "Vietcombank\nSố tiền 500.000 VND\nNội dung: tien nha thang 10"
    #expect(classify(text, createdAt: TestSupport.daysAgo(400)).category == .transferReceipt)
  }

  @Test("ambiguous bank word with only generic fields is not a receipt")
  func ambiguousBankWord() {
    let text = "Mua cake nhé\nSố tiền 300.000đ\nNội dung ghi cake"
    #expect(classify(text).category == .other)
  }

  @Test("ambiguous bank name with a receipt-only field is a receipt")
  func ambiguousBankWithStrongField() {
    let text = "MB\nSố tiền 500.000 VND\nMã giao dịch FT123"
    #expect(classify(text).category == .transferReceipt)
  }

  @Test("a shop name alone is not an order screen")
  func brandAloneIsNotOrder() {
    let text = "Shopee Live hôm nay giảm giá\nĐơn hàng trên 99k được freeship"
    #expect(classify(text, createdAt: TestSupport.daysAgo(60)).category == .other)
  }

  @Test("two generic travel words make a ticket, one does not")
  func genericTravelWords() {
    #expect(
      classify("Gate 5\nSeat 12A", createdAt: TestSupport.daysAgo(40)).category == .expiredTicket)
    #expect(classify("Khởi hành lúc 08:15", createdAt: TestSupport.daysAgo(40)).category == .other)
  }

  @Test("plain text with nothing to match is other / none")
  func other() {
    #expect(classify("Cài đặt\nWi-Fi\nBluetooth") == .other)
  }
}
