import Foundation
import Testing

@testable import ShotCleanCore

@Suite("DateExtractor")
struct DateExtractorTests {
  let calendar = TestSupport.calendar
  let reference = TestSupport.now  // 15/10/2026

  func extract(_ text: String) -> [Date] {
    DateExtractor.dates(in: text, reference: reference, calendar: calendar)
  }

  @Test(
    "parses explicit full-date formats",
    arguments: [
      "Ngày 12/09/2026",
      "12-09-2026",
      "12.09.2026",
      "12/09/26",
      "2026-09-12",
      "12 thg 9, 2026",
      "12 tháng 9 2026",
      "Ngày 12 tháng 09 năm 2026",
      "12/9/2026",
    ])
  func parsesFormats(text: String) {
    #expect(extract(text) == [TestSupport.date(2026, 9, 12)])
  }

  @Test("dd/MM without year uses the reference year when not far in the future")
  func inferYearCurrent() {
    #expect(extract("Giao ngày 12/09") == [TestSupport.date(2026, 9, 12)])
    // 01/12/2026 is 47 days after the reference → still this year.
    #expect(extract("Hẹn 01/12") == [TestSupport.date(2026, 12, 1)])
  }

  @Test("dd/MM more than 60 days after the reference rolls back one year")
  func inferYearPrevious() {
    // 20/12/2026 would be 66 days after 15/10/2026.
    #expect(extract("Đặt hàng 20/12") == [TestSupport.date(2025, 12, 20)])
  }

  @Test(
    "Vietnamese month forms with odd spacing",
    arguments: ["12thg9 2026", "ngày 12 tháng 9 năm 2026", "12 THG 9 , 2026", "12 thang 09"])
  func vietnameseSpacing(text: String) {
    #expect(extract(text) == [TestSupport.date(2026, 9, 12)])
  }

  @Test("dates glued to letters or emoji are found; glued to numbers are not")
  func scannerBoundaries() {
    #expect(extract("Ngày12/09/2026😂") == [TestSupport.date(2026, 9, 12)])
    #expect(extract("1-12/09/2026").isEmpty)
    #expect(extract("12/09/20261").isEmpty)
    #expect(extract("12/09/2026.5").isEmpty)
  }

  @Test("'12 thg 9' without a year is inferred like dd/MM")
  func vietnameseMonthWithoutYear() {
    #expect(extract("12 thg 9") == [TestSupport.date(2026, 9, 12)])
  }

  @Test(
    "ignores invalid calendar dates",
    arguments: ["32/13/2026", "31/02/2026", "00/05/2026", "15/00/2026", "2026-13-01"])
  func invalid(text: String) {
    #expect(extract(text).isEmpty)
  }

  @Test(
    "does not mistake amounts, times, phone or account numbers for dates",
    arguments: [
      "1.250.000đ",
      "Số tiền 12.500.000 VND",
      "500,000 VND",
      "10:15",
      "lúc 09:15:22",
      "0912.345.678",
      "STK 1903 1234 5678",
      "Giảm 10.5%",
      "12.05",
      "Trang 1/2",
    ])
  func notDates(text: String) {
    #expect(extract(text).isEmpty)
  }

  @Test("returns every distinct date, sorted ascending")
  func multipleDates() {
    let text = "Đặt 01/09/2026 · Giao 05/09/2026 · Cập nhật 2026-09-05 10:15"
    #expect(extract(text) == [TestSupport.date(2026, 9, 1), TestSupport.date(2026, 9, 5)])
  }

  @Test("date next to a time is still found")
  func dateWithTime() {
    #expect(extract("Giờ khởi hành: 22:30 01/10/2026") == [TestSupport.date(2026, 10, 1)])
    #expect(extract("14:32 Thứ Hai 12/10/2026") == [TestSupport.date(2026, 10, 12)])
  }

  @Test("dates are start of day in the supplied calendar's time zone")
  func respectsCalendarTimeZone() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let dates = DateExtractor.dates(in: "12/09/2026", reference: reference, calendar: utc)
    #expect(dates == [utc.date(from: DateComponents(year: 2026, month: 9, day: 12))])
  }
}
