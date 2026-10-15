import Foundation

/// Keyword lists used by the rules. Every entry is stored ALREADY folded
/// (lowercase, no diacritics, `đ` → `d`) and is matched as whole tokens against
/// `TextNormalizer.fold(text)` via `TokenizedText`.
enum Keywords {
  /// Phrases that by themselves say "a transfer/payment succeeded".
  static let transferSuccess = phrases([
    "chuyen tien thanh cong",
    "chuyen khoan thanh cong",
    "giao dich thanh cong",
    "thanh toan thanh cong",
    "giao dich da hoan tat",
    "transfer successful",
    "transaction successful",
    "payment successful",
  ])

  /// Banks and e-wallets whose names are not ordinary words.
  static let banksAndWallets = phrases([
    "vietcombank", "techcombank", "mbbank", "mb bank", "bidv",
    "vietinbank", "agribank", "tpbank", "vpbank", "sacombank", "hdbank",
    "seabank", "eximbank", "lpbank", "nam a bank", "bac a bank",
    "abbank", "ubank", "momo", "zalopay", "vnpay", "shopeepay",
    "viettel money", "viettelpay",
  ])

  /// Bank names that are also common words or short acronyms ("cake", "MB" = megabyte, …).
  /// They only count together with a strong transfer field (BUG-2).
  static let ambiguousBanks = phrases([
    "vcb", "tcb", "mb", "acb", "vib", "shb", "ocb", "msb", "timo", "cake",
  ])

  /// Field labels that only appear on transfer receipts.
  static let strongTransferFields = phrases([
    "ma giao dich", "ma gd", "tai khoan nhan", "tai khoan thu huong", "nguoi thu huong",
    "ngan hang thu huong", "so tai khoan", "ngan hang nhan",
  ])

  /// Field labels shared with chats and order screens ("Người nhận" is also a shipping label).
  static let weakTransferFields = phrases(["so tien", "noi dung", "nguoi nhan"])

  /// Ticket-specific labels. Bare "ve" is intentionally absent: "về" (to return) also folds to
  /// "ve", so only compound forms are used.
  static let ticketStrong = phrases([
    "ve xe", "ve tau", "ve may bay", "ve dien tu", "ve xem phim", "ma ve", "so ve", "loai ve",
    "gia ve", "chuyen bay", "boarding", "boarding pass", "the len may bay", "the len tau bay",
    "ma dat cho", "pnr", "cho ngoi", "so ghe", "ghe ngoi", "nha xe",
  ])

  /// Generic travel words (maps, schedules, UI). Two different ones are needed (BUG-4).
  static let ticketWeak = phrases(["khoi hanh", "flight", "gate", "seat"])

  /// Shops and carriers.
  static let orderBrands = phrases([
    "shopee", "lazada", "tiktok shop", "tiki", "sendo", "ghn", "giao hang nhanh", "ghtk",
    "giao hang tiet kiem", "j&t", "j&t express", "spx", "spx express", "ninja van",
    "viettel post", "lex vn",
  ])

  /// Labels that identify a concrete order / parcel on their own.
  static let orderIdentifiers = phrases([
    "ma van don", "ma don hang", "chi tiet don hang", "thong tin don hang", "tra cuu don hang",
    "hanh trinh don hang",
  ])

  /// Order status labels; they need a brand or an identifier as well (BUG-3).
  static let orderStatus = phrases([
    "da giao", "dang giao", "giao hang thanh cong", "da nhan hang", "dang van chuyen",
    "da ky nhan", "cho giao hang", "cho lay hang", "du kien giao", "don hang da giao",
  ])

  static func phrases(_ list: [String]) -> [Phrase] { list.map(Phrase.init) }
}

/// A folded keyword split into words, with its space-padded UTF-8 needle precomputed.
struct Phrase: Sendable {
  let words: [ArraySlice<UInt8>]
  let needle: [UInt8]

  init(_ text: String) {
    words = Array(text.utf8).split(separator: UInt8(ascii: " "))
    needle = Array(" \(text) ".utf8)
  }
}

/// Folded text tokenized once per screenshot (BUG-6); phrase lookups are a set check per word
/// plus, for multi-word phrases whose words all occur, one byte search.
struct TokenizedText {
  /// `" tok tok … "` as UTF-8: every scalar that cannot be part of a keyword token (anything
  /// but letters, digits and `&`) becomes a single space.
  private let padded: [UInt8]
  private let tokens: Set<ArraySlice<UInt8>>

  init(folded: String) {
    let space = UInt8(ascii: " ")
    var bytes: [UInt8] = [space]
    bytes.reserveCapacity(folded.utf8.count + 2)
    var lastWasSpace = true
    for scalar in folded.unicodeScalars {
      if scalar.isASCII {
        let value = UInt8(scalar.value)
        if (value >= 0x61 && value <= 0x7A) || (value >= 0x41 && value <= 0x5A)
          || (value >= 0x30 && value <= 0x39) || value == UInt8(ascii: "&")
        {
          bytes.append(value)
          lastWasSpace = false
          continue
        }
      } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil,
        let encoded = UTF8.encode(scalar)
      {
        bytes.append(contentsOf: encoded)
        lastWasSpace = false
        continue
      }
      if !lastWasSpace {
        bytes.append(space)
        lastWasSpace = true
      }
    }
    if !lastWasSpace { bytes.append(space) }
    padded = bytes
    tokens = Set(bytes.split(separator: space))
  }

  func contains(_ phrase: Phrase) -> Bool {
    guard phrase.words.allSatisfy(tokens.contains) else { return false }
    if phrase.words.count == 1 { return true }
    return padded.withUnsafeBufferPointer { haystack in
      phrase.needle.withUnsafeBufferPointer { needle in
        Self.find(needle, in: haystack)
      }
    }
  }

  func containsAny(_ phrases: [Phrase]) -> Bool {
    phrases.contains(where: contains)
  }

  func count(of phrases: [Phrase]) -> Int {
    phrases.reduce(0) { $0 + (contains($1) ? 1 : 0) }
  }

  /// `true` if the tokens of `first` are immediately followed by the tokens of `second`.
  func containsSequence(_ first: Phrase, _ second: Phrase) -> Bool {
    guard contains(first), contains(second) else { return false }
    // " first " + "second " → " first second "
    let needle = first.needle + second.needle.dropFirst()
    return padded.withUnsafeBufferPointer { haystack in
      needle.withUnsafeBufferPointer { Self.find($0, in: haystack) }
    }
  }

  private static func find(
    _ needle: UnsafeBufferPointer<UInt8>, in haystack: UnsafeBufferPointer<UInt8>
  ) -> Bool {
    guard let first = needle.first, needle.count <= haystack.count else { return false }
    var index = 0
    let last = haystack.count - needle.count
    while index <= last {
      if haystack[index] == first {
        var offset = 1
        while offset < needle.count, haystack[index + offset] == needle[offset] { offset += 1 }
        if offset == needle.count { return true }
      }
      index += 1
    }
    return false
  }
}
