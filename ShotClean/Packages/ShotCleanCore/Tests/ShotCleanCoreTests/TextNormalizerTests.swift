import Testing

@testable import ShotCleanCore

@Suite("TextNormalizer.fold")
struct TextNormalizerTests {
  @Test(
    "lowercases, strips diacritics and maps đ to d",
    arguments: [
      ("Chuyển tiền THÀNH CÔNG", "chuyen tien thanh cong"),
      ("Đơn hàng đã giao", "don hang da giao"),
      ("ĐẶT CHỖ", "dat cho"),
      ("Mã giao dịch", "ma giao dich"),
      ("Giờ khởi hành", "gio khoi hanh"),
      ("Số tiền", "so tien"),
      ("Ngày 12 tháng 9", "ngay 12 thang 9"),
      ("Tài khoản nhận", "tai khoan nhan"),
      ("Ưu đãi", "uu dai"),
    ])
  func folds(input: String, expected: String) {
    #expect(TextNormalizer.fold(input) == expected)
  }

  @Test("collapses whitespace and newlines, trims ends")
  func collapsesWhitespace() {
    #expect(TextNormalizer.fold("  Vé  xe\n\n\tkhách \r\n 22:30 ") == "ve xe khach 22:30")
  }

  @Test("decomposed (NFD) input folds the same as composed input")
  func decomposedInput() {
    let decomposed = "Thành công".decomposedStringWithCanonicalMapping
    #expect(TextNormalizer.fold(decomposed) == "thanh cong")
  }

  @Test("keeps digits and punctuation")
  func keepsDigits() {
    #expect(TextNormalizer.fold("1.250.000 VNĐ 10:15") == "1.250.000 vnd 10:15")
  }

  @Test("empty and whitespace-only strings fold to empty")
  func empty() {
    #expect(TextNormalizer.fold("") == "")
    #expect(TextNormalizer.fold(" \n\t ") == "")
  }
}
