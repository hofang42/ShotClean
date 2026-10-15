# ShotCleanCore — bugs found by tests (R3)

Each bug has a failing test kept in the suite under `withKnownIssue("BUG-n …")`.
When a bug is fixed the known-issue block starts failing ("known issue was not recorded") —
remove the wrapper (and the `knownIssue` field in `Fixtures/manifest.json`) at that point.

| ID | Severity | Test |
|---|---|---|
| BUG-1 (FIXED) | Low (safe: keeps) | `FixtureTests.fixtureVerdict` → `order_shopee_shopeepay_old.txt` |
| BUG-2 (FIXED) | Low (safe: keeps) | `FixtureTests.fixtureVerdict` → `chat_birthday_cake.txt` |
| BUG-3 (FIXED) | Medium (false delete) | `FixtureTests.fixtureVerdict` → `news_shopee_article.txt`, `deletePrecisionAll` |
| BUG-4 (FIXED) | Medium (false delete) | `FixtureTests.fixtureVerdict` → `maps_transit_khoi_hanh.txt`, `deletePrecisionAll` |
| BUG-5 (FIXED) | High (deletes a valid upcoming ticket) | `BoundaryEdgeTests.yearBoundaryForward`, `yearBoundaryUpcomingTicket` |
| BUG-6 (FIXED) | Low (perf) | `ClassifierInputEdgeTests.hugeTextPerformance` |

## BUG-1 — FIXED — Shopee order paid by ShopeePay is treated as a transfer receipt
- **Input:** Shopee order detail, `Người nhận: TRAN THI MAI …` (shipping address), `Thành tiền ₫189.000`,
  `Phương thức thanh toán: ShopeePay`; captured 2026-08-01, now 2026-10-15.
- **Expected:** `expiredOrder` / `delete`.
- **Actual:** `transferReceipt` / `keep`.
- **Suspected cause:** receipt rule = bank/wallet keyword (`shopeepay`) + transfer field (`nguoi nhan`)
  + amount. Shipping-address labels on order screens share the field "Người nhận". Consider requiring
  a success phrase or ≥ 2 transfer fields when the only wallet hit is a payment-method label, or
  checking for order keywords first when no success phrase is present.

## BUG-2 — FIXED — Chat containing the word "cake" is treated as a Cake-bank receipt
- **Input:** group chat: `Ai mua cake sinh nhật…`, `số tiền 450.000đ`, `nội dung chuyển khoản ghi gì?`.
- **Expected:** `other` / `none`.
- **Actual:** `transferReceipt` / `keep`.
- **Suspected cause:** `Keywords.banksAndWallets` contains common English words (`cake`, also `timo`,
  `mb`, `vib`…) matched as bare tokens; together with "số tiền"/"nội dung" + amount the rule fires.
  Safe direction (keep) but pollutes the receipt group. Consider requiring the bank token near a
  receipt header/success phrase, or dropping ambiguous names unless combined with "bank".

## BUG-3 — FIXED — Old news article about Shopee suggested for deletion as an expired order
- **Input:** VnExpress article "Shopee tăng phí người bán…", mentions `đơn hàng`, `vận chuyển`,
  dated `3/8/2026`; captured 2026-08-05.
- **Expected:** `other` / `none`.
- **Actual:** `expiredOrder` / `delete` ("Đơn hàng từ 03/08 — đã quá 30 ngày").
- **Suspected cause:** order rule fires on any single order keyword (`shopee`, `don hang`,
  `van chuyen`) — brand names alone are not evidence of an order screen. Consider requiring an
  order-screen signal (`ma don hang`, `ma van don`, `da giao`, `dang giao`, tracking id) in addition
  to a brand.
- **Impact:** together with BUG-4 drops fixture delete precision to 13/15 = 0.867 (< 0.95 target).

## BUG-4 — FIXED — Maps transit directions ("Khởi hành lúc") suggested for deletion as an expired ticket
- **Input:** `Phương tiện công cộng / Khởi hành lúc 08:15 / Xe buýt 19 … / 7.000đ`; captured
  2026-08-01, no date in text.
- **Expected:** `other` / `none`.
- **Actual:** `expiredTicket` / `delete` ("Vé chụp hơn 30 ngày trước").
- **Suspected cause:** `khoi hanh` (depart) alone is a ticket keyword; generic UI words like
  "khởi hành", "gate", "seat", "flight" should need a second ticket signal (booking code, seat,
  `ve …`) before the rule applies, especially on the no-date/age fallback path.

## BUG-5 — FIXED — Year-less date never rolls forward into the next year
- **Input:** `DateExtractor.dates(in: "Ngày đi 02/01", reference: 30/12/2025)`; and a ticket
  `Vé xe … Giờ khởi hành 22:00 02/01` captured 30/12/2025, now 31/12/2025.
- **Expected:** `[02/01/2026]`; ticket verdict `other` (upcoming trip).
- **Actual:** `[02/01/2025]`; ticket verdict `expiredTicket` / `delete` ("Vé ngày 02/01/2025 đã qua").
- **Suspected cause:** `DateExtractor.makeDate` only ever tries the reference year and the previous
  year. A year-less date that lies just after a year end (e.g. Tết / New Year trips booked in late
  December) should take `referenceYear + 1` when that lands within the 60-day forward window.
  This can preselect a valid future ticket for deletion.

## BUG-6 — FIXED — Classifying 50 KB of OCR text takes ~80–120 ms (budget 50 ms)
- **Input:** ~50 KB of repeated order lines (`Shopee Đơn hàng đã giao 12/08/2026 …`).
- **Expected:** < 50 ms per `classify`.
- **Actual:** 78–117 ms on Linux (debug and release); `fold` ≈ 14 ms, `DateExtractor` ≈ 18 ms,
  the remaining ~50–80 ms is in keyword/amount matching.
- **Suspected cause:** `Keywords.containsAny` re-runs `tokenized(folded)` (a per-Character map +
  split/join of the whole text) for every keyword list (up to 5× per image), and
  `containsAmount` compiles 3 `NSRegularExpression`s on every call. Tokenize once per image and
  cache compiled regexes as statics. Real OCR text is usually < 5 KB, so impact is low.

## Status (R7a core-fixer, 2026-10-15) — all FIXED, no known issues left in the Core suite
All `withKnownIssue` wrappers and `knownIssue` manifest fields were removed; the tests assert normally.
Fixture delete precision: 14/14 = 1.0, 0 receipts suggested for deletion.

- **BUG-1 — FIXED.** Receipt rule now needs a success phrase, or a bank/wallet + a receipt-only field (`ma giao dich`, `tai khoan nhan`, `so tai khoan`, …), or an unambiguous bank + ≥ 2 generic fields (`so tien`/`noi dung`/`nguoi nhan`) with no order-screen signal; a ShopeePay order with a shipping "Người nhận" is an order again.
- **BUG-2 — FIXED.** Ambiguous bank names (`cake`, `timo`, `mb`, `vib`, `vcb`, `tcb`, `acb`, `shb`, `ocb`, `msb`) only count together with a receipt-only field.
- **BUG-3 — FIXED.** Order rule needs an order identifier (`ma van don`, `ma don hang`, `chi tiet don hang`…), or a status (`da giao`, `dang giao`, `giao hang thanh cong`…) plus a shop/carrier, or "đơn hàng" directly next to a shop/carrier name; a brand mentioned in prose is not enough.
- **BUG-4 — FIXED.** Ticket rule needs a ticket-specific label (`ve xe`, `ve tau`, `chuyen bay`, `boarding`, `ma dat cho`, `pnr`, `so ghe`, `cho ngoi`, `nha xe`…) or two different generic words (`khoi hanh`, `flight`, `gate`, `seat`).
- **BUG-5 — FIXED.** `DateExtractor` tries previous/same/next year and keeps the candidate closest to the capture date among those ≤ 60 days after it (the 60-day forward window is kept because `inferYearPrevious` pins it: `20/12` read on 15/10 → last year).
- **BUG-6 — FIXED.** Text folded once per image (`DateExtractor.dates(inFolded:)`), tokenized once into a byte buffer + token set (`TokenizedText`), single-pass `fold`, precompiled amount regex, and the four date regexes replaced by an equivalent single-pass byte scanner; dates are built once per distinct day. 50 KB classify ≈ 7 ms isolated, 11–28 ms under the parallel suite in release, ≈ 25 ms debug — the 50 ms assertion runs unchanged in both configurations.
- **REV-4 (Core side) — FIXED.** `ScreenshotClassifier` treats a capture date before 2000-01-01 (e.g. `.distantPast`) as unknown: QR age, ticket no-date and order capture-date fallbacks are skipped and year-less dates are read relative to `now` (test `BoundaryEdgeTests.unknownCaptureDate`). The app should still stop passing `.distantPast`.
