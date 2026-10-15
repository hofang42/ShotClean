import Foundation

/// Keyword lists used by the rules. Every entry is stored ALREADY folded
/// (lowercase, no diacritics, `đ` → `d`) and is matched as whole tokens against
/// `TextNormalizer.fold(text)` (see `Keywords.contains(_:in:)`).
enum Keywords {
  /// Phrases that by themselves say "a transfer/payment succeeded".
  static let transferSuccess: [String] = [
    "chuyen tien thanh cong",
    "chuyen khoan thanh cong",
    "giao dich thanh cong",
    "thanh toan thanh cong",
    "giao dich da hoan tat",
    "transfer successful",
    "transaction successful",
    "payment successful",
  ]

  /// Banks and e-wallets common in Vietnam.
  static let banksAndWallets: [String] = [
    "vietcombank", "vcb", "techcombank", "tcb", "mb", "mbbank", "mb bank", "bidv",
    "vietinbank", "agribank", "acb", "tpbank", "vpbank", "sacombank", "hdbank", "vib",
    "shb", "ocb", "msb", "seabank", "eximbank", "lpbank", "nam a bank", "bac a bank",
    "abbank", "timo", "cake", "ubank", "momo", "zalopay", "vnpay", "shopeepay",
    "viettel money", "viettelpay",
  ]

  /// Field labels found on transfer receipts.
  static let transferFields: [String] = [
    "so tien", "ma giao dich", "ma gd", "noi dung", "tai khoan nhan", "tai khoan thu huong",
    "nguoi nhan", "nguoi thu huong", "ngan hang thu huong", "so tai khoan",
  ]

  /// Ticket keywords. Bare "ve" is intentionally absent: "về" (to return) also folds to "ve",
  /// so only compound forms are used.
  static let ticket: [String] = [
    "ve xe", "ve tau", "ve may bay", "ve dien tu", "ve xem phim", "ma ve", "so ve", "loai ve",
    "gia ve", "chuyen bay", "gio khoi hanh", "khoi hanh", "boarding", "boarding pass",
    "the len may bay", "the len tau bay", "ma dat cho", "pnr", "flight", "gate", "cho ngoi",
    "so ghe", "ghe ngoi", "seat",
  ]

  /// Shopping / shipping keywords.
  static let order: [String] = [
    "shopee", "lazada", "tiktok shop", "tiki", "sendo", "ghn", "giao hang nhanh", "ghtk",
    "giao hang tiet kiem", "j&t", "j&t express", "spx", "spx express", "ninja van",
    "viettel post", "ma van don", "ma don hang", "don hang", "da giao", "dang giao",
    "van chuyen",
  ]

  /// `true` if any keyword occurs in `folded` as a whole-token phrase.
  static func containsAny(_ keywords: [String], in folded: String) -> Bool {
    let padded = tokenized(folded)
    return keywords.contains { padded.contains(" \($0) ") }
  }

  /// Replaces every character that cannot be part of a keyword token with a space and pads
  /// both ends, so `" mb "` matches "MB" but not "mbps" and `"giao dich thanh cong!"` matches.
  static func tokenized(_ folded: String) -> String {
    let mapped = folded.map { character -> Character in
      character.isLetter || character.isNumber || character == "&" ? character : " "
    }
    let collapsed = String(mapped).split(separator: " ").joined(separator: " ")
    return " \(collapsed) "
  }
}
