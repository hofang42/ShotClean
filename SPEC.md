# Spec: ShotClean — dọn ảnh chụp màn hình trên iOS

> Trạng thái: **DRAFT, chờ duyệt** · Cập nhật: 2026-10-15
> Bối cảnh research: `deep-dive-*.md` trong thư mục này · Giao diện: [UI-SPEC.md](UI-SPEC.md) + [ui-mockup.html](ui-mockup.html)

## Giả định (sửa ngay nếu sai)
1. Native iOS app viết bằng Swift + SwiftUI, **iOS 17+**, chỉ iPhone (không làm iPad layout riêng).
2. Build bằng **xtool trên WSL2** → `.ipa` chưa ký → ký và cài bằng **Sideloadly** trên Windows. Không dùng Mac/Xcode.
3. Giai đoạn 1 là **tự dùng (sideload)**. Spec chừa sẵn đường lên App Store (mua 1 lần) nhưng không làm trong POC/MVP.
4. **100% on-device**: app không có code mạng, không analytics, không upload ảnh hay text.
5. UI tiếng Việt trước. Code, tên biến, log bằng tiếng Anh.
6. Bắt đầu từ thư mục trống `D:\DuAnMa\Clean`, chưa có code.

## Objective
**Vấn đề:** Album "Ảnh chụp màn hình" phình to vì ảnh trùng, QR dùng một lần, đơn hàng/vé đã hết hạn. Dọn tay thì mất thời gian, và dễ xoá nhầm biên lai quan trọng.

**Người dùng:** người dùng iPhone ở VN chụp màn hình nhiều (chuyển khoản, mua sắm online, đi lại). Người dùng đầu tiên là chính tác giả.

**Giải pháp:** App quét **chỉ ảnh chụp màn hình**, phân loại nội dung on-device rồi đề xuất xoá hoặc giữ, mỗi đề xuất kèm lý do. Người dùng xem lại và xoá hàng loạt với **một lần xác nhận hệ thống**.

**Khác biệt so với các app "Cleaner":** hiểu nội dung ảnh (không chỉ tìm trùng), chủ động bảo vệ biên lai, privacy on-device, mua 1 lần thay vì subscription.

### User stories
- **US1:** Mở app lần đầu → cấp quyền Photos → thấy tổng số ảnh chụp màn hình và số ảnh trong từng nhóm.
- **US2:** Xem nhóm **Trùng hoàn toàn** → mỗi cụm giữ 1 ảnh (mặc định ảnh cũ nhất), các ảnh còn lại được chọn sẵn để xoá.
- **US3:** Xem nhóm **Gần trùng** → mỗi cụm hiện các ảnh cạnh nhau, người dùng chọn ảnh giữ lại. Không chọn sẵn để xoá.
- **US4:** Xem nhóm **QR không cần thiết** → ảnh chủ yếu là mã QR và cũ hơn N ngày được chọn sẵn để xoá.
- **US5:** Xem nhóm **Đơn hàng / vé đã hết hạn** → ảnh có mốc ngày đã qua (cộng thêm thời gian ân hạn) được chọn sẵn để xoá. Mỗi ảnh hiện lý do, ví dụ: "Vé ngày 12/09/2026 đã qua".
- **US6:** Ảnh **biên lai chuyển khoản** được gắn nhãn **"Giữ lại"**, không bao giờ được chọn sẵn để xoá. Người dùng vẫn có thể tự chọn xoá.
- **US7:** Bấm "Xoá N ảnh" → hiện hộp thoại xác nhận của iOS → ảnh chuyển vào "Đã xoá gần đây" (30 ngày). App báo số ảnh đã dọn và dung lượng ước tính đã giải phóng.
- **US8:** Mở lại app → chỉ phân tích ảnh mới (có cache). Có thể bấm "Quét lại toàn bộ".

## Scope

| Phase | Trong scope | Mục tiêu |
|---|---|---|
| **POC** | Build và sideload chạy được · fetch ảnh chụp màn hình · OCR + phát hiện QR + FeaturePrint + hash · rules engine cho các nhóm · màn Tổng quan (S4) + Lưới theo nhóm (S5) + **Chế độ vuốt (S7)** theo [UI-SPEC](UI-SPEC.md) · màn hình debug liệt kê ảnh, nhóm, lý do · xoá hàng loạt | Chứng minh các rủi ro kỹ thuật (R1–R5) và độ chính xác phân loại |
| **MVP (tự dùng)** | UI review theo nhóm (US1–US8) · cache kết quả phân tích · xử lý quyền truy cập giới hạn (limited access) · cài đặt các ngưỡng (N ngày, ân hạn) · thống kê dung lượng | Dùng hằng tuần trên máy thật |
| **v1 App Store** (sau) | StoreKit 2 non-consumable (mua 1 lần) · free tier có giới hạn · onboarding · privacy label · tiếng Anh · icon chuẩn | Phát hành |

**Ngoài scope cho tới khi có quyết định mới:**
- OTP / mã xác nhận (để v1.1)
- meme / ảnh từ mạng xã hội
- tự xoá chạy nền (iOS không cho phép)
- thông báo nhắc dọn định kỳ (cân nhắc ở MVP+)
- lưu text ra ghi chú trước khi xoá
- Foundation Models / LLM
- iCloud sync, iPad, Android
- ảnh không phải ảnh chụp màn hình

## Phân loại (rules) — định nghĩa cho POC

Mỗi ảnh nhận **một nhóm chính** và **một đề xuất** (`delete` / `keep` / `review`), kèm `reason` đọc được.

**Thứ tự ưu tiên khi một ảnh khớp nhiều rule:** `transferReceipt` > `exactDuplicate` > `expiredTicket` / `expiredOrder` > `qrCode` > `nearDuplicate` > `other`.

| Nhóm | Cách phát hiện (on-device) | Đề xuất mặc định |
|---|---|---|
| `transferReceipt` | OCR + từ khoá đã bỏ dấu ("chuyen tien thanh cong", "giao dich thanh cong", "so tien", "ma giao dich", tên ngân hàng/ví: Vietcombank, Techcombank, MB, BIDV, VietinBank, ACB, TPBank, VPBank, MoMo, ZaloPay...) và có pattern số tiền (`\d{1,3}([.,]\d{3})+ ?(VND\|đ)`) | **keep**, không bao giờ preselect |
| `exactDuplicate` | SHA-256 dữ liệu ảnh gốc (`PHAssetResource`). Fallback: cùng kích thước pixel và khoảng cách FeaturePrint ≈ 0 | **delete** mọi ảnh trừ ảnh cũ nhất trong cụm |
| `expiredTicket` | OCR có từ khoá vé ("ve", "gio khoi hanh", "chuyen bay", "boarding", "ma dat cho", "PNR"...) + ngày lớn nhất trong text < hôm nay − ân hạn (mặc định 1 ngày) | **delete** |
| `expiredOrder` | OCR có từ khoá đơn hàng/vận chuyển (Shopee, Lazada, TikTok Shop, Tiki, GHN, GHTK, J&T, SPX, "ma van don", "da giao", "don hang") + ảnh cũ hơn 30 ngày, hoặc ngày giao trong text đã qua 30 ngày | **delete** |
| `qrCode` | `VNDetectBarcodesRequest` tìm thấy QR, tổng diện tích QR ≥ 15% ảnh, ảnh cũ hơn 7 ngày, và **không** phải `transferReceipt` | **delete** |
| `nearDuplicate` | Khoảng cách `VNFeaturePrintObservation` < ngưỡng T (tinh chỉnh trong POC), ảnh chụp cách nhau ≤ 10 phút | **review** (không preselect) |
| `other` | Không khớp rule nào | không đề xuất |

Mọi ngưỡng (7 ngày, 30 ngày, 15%, T, 10 phút) là **hằng số cấu hình trong Core**, sẽ tinh chỉnh bằng bộ ảnh thật ở POC.

## Tech Stack
- **Swift 6.4** toolchain (Linux, WSL2 Ubuntu) + **xtool** (latest release AppImage) + iOS SDK sinh từ **Xcode 27** `.xip`.
- Frameworks của Apple (không thêm dependency bên thứ ba): SwiftUI, Photos/PhotoKit, Vision, CryptoKit, Observation.
- Test: **Swift Testing** (`import Testing`) cho Core, chạy được trên Linux.
- Format/lint: `swift format` có sẵn trong toolchain Swift 6.
- Ký và cài: Sideloadly (Windows). Log khi chạy: `idevicesyslog` (libimobiledevice-utils).

## Commands
Chạy trong WSL. Nên clone repo vào filesystem của WSL (`~/src/Clean`) vì build trên `/mnt/d` chậm.
```bash
# Build .ipa chưa ký → ShotClean/xtool/ShotClean.ipa
cd ShotClean && xtool dev build --ipa

# Unit test Core (Linux, không cần iOS SDK)
cd ShotClean/Packages/ShotCleanCore && swift test

# Format / lint
swift format format -i -r ShotClean/Sources ShotClean/Packages/ShotCleanCore
swift format lint -r ShotClean/Sources ShotClean/Packages/ShotCleanCore

# Xem log app trên máy (thiết bị đã attach qua usbipd hoặc relay iTunes)
idevicesyslog | grep ShotClean
```
Cài đặt: kéo `ShotClean.ipa` vào Sideloadly → Start → trên iPhone bật Developer Mode và tin cậy chứng chỉ.

## Project Structure
```
D:\DuAnMa\Clean\
├── SPEC.md                         → spec này (nguồn sự thật)
├── deep-dive-*.md                  → research đã làm (giữ nguyên)
├── tasks/                          → plan.md, todo.md (Phase 2–3)
└── ShotClean/                      → project xtool
    ├── Package.swift               → app target, phụ thuộc ShotCleanCore theo path
    ├── xtool.yml                   → bundleID, infoPath, iconPath
    ├── Support/
    │   ├── Info.plist              → NSPhotoLibraryUsageDescription
    │   └── AppIcon.png             → 1024×1024, không dùng .xcassets (tránh actool)
    ├── Sources/ShotClean/
    │   ├── App/                    → @main, AppState
    │   ├── Views/                  → SwiftUI screens (Overview, CategoryList, ClusterReview, Debug)
    │   ├── Library/                → PhotoKit: fetch screenshots, load data, delete
    │   └── Analysis/               → Vision: OCR, barcode, FeaturePrint, SHA-256 → ScreenshotFeatures
    └── Packages/ShotCleanCore/     → package Swift thuần, CHỈ dùng Foundation (test được trên Linux)
        ├── Package.swift
        ├── Sources/ShotCleanCore/  → models, text normalize (bỏ dấu), date parser, rules, clustering
        └── Tests/ShotCleanCoreTests/
            └── Fixtures/           → OCR text đã ẩn danh (.txt) + expected category
```
**Ranh giới quan trọng:** `ShotCleanCore` không import Photos, Vision hay SwiftUI. App lấy feature từ ảnh rồi đưa cho Core. Core chỉ nhận `ScreenshotFeatures` và trả về `Verdict`. Nhờ vậy logic phân loại test được trên Linux.

## Code Style
- Swift 6 language mode, strict concurrency. Không có `@unchecked Sendable` trừ khi đã ghi rõ lý do.
- Type `UpperCamelCase`, member `lowerCamelCase`, không viết tắt khó hiểu. Một type chính mỗi file.
- Không dùng force unwrap (`!`) ngoài test.
- Truyền `localIdentifier` (String) qua các ranh giới concurrency, không truyền `PHAsset`.
- Text trước khi match luôn đi qua `TextNormalizer.fold` (lowercase, bỏ dấu, gộp khoảng trắng).
- Ngưỡng nằm trong `Thresholds`, không hard-code rải rác.

```swift
public struct ScreenshotFeatures: Sendable, Codable, Equatable {
    public let id: String            // PHAsset.localIdentifier
    public let createdAt: Date
    public let pixelSize: PixelSize
    public let text: String          // OCR thô
    public let qrAreaRatio: Double   // 0...1, tổng diện tích QR / ảnh
    public let sha256: String?
}

public enum Category: String, Sendable, Codable {
    case transferReceipt, exactDuplicate, expiredTicket, expiredOrder, qrCode, nearDuplicate, other
}

public struct Verdict: Sendable, Equatable {
    public enum Suggestion: Sendable, Equatable { case delete, keep, review, none }
    public let category: Category
    public let suggestion: Suggestion
    public let reason: String        // tiếng Việt, hiển thị cho người dùng
}

public protocol ScreenshotRule: Sendable {
    func evaluate(_ features: ScreenshotFeatures, now: Date) -> Verdict?
}
```

## Testing Strategy
| Lớp | Công cụ | Chạy ở đâu | Nội dung |
|---|---|---|---|
| Unit (Core) | Swift Testing | WSL/Linux, `swift test` | TextNormalizer, DateParser (dd/MM/yyyy, dd/MM, "12 thg 9"), từng rule, thứ tự ưu tiên, clustering từ distance matrix |
| Fixture | Swift Testing + `Fixtures/*.txt` | Linux | ≥ 30 mẫu OCR text đã ẩn danh từ ảnh thật, mỗi mẫu có expected category |
| On-device | Màn hình Debug + checklist thủ công | iPhone thật | Đánh nhãn tay ≥ 100 ảnh chụp màn hình thật, so với kết quả của app |
| Perf | Đo thời gian trong Debug view | iPhone thật | Thời gian phân tích mỗi ảnh và tổng thời gian cho 1.000 ảnh |

- Core: mọi rule có test cả trường hợp đúng lẫn sai. Không đặt mục tiêu coverage % cho UI.
- Bug phân loại: viết fixture tái hiện trước rồi mới sửa (Prove-It).

## Rủi ro kỹ thuật POC phải trả lời
| ID | Rủi ro | Cách kiểm chứng trong POC | Fallback |
|---|---|---|---|
| R1 | Vision OCR trên iOS 17 có hỗ trợ tiếng Việt không, chất lượng ra sao | Log `supportedRecognitionLanguages()`, đo trên 30 ảnh | Nhận diện ở chế độ `.accurate` với `en-US` + so khớp từ khoá đã bỏ dấu |
| R2 | xtool build và link Photos/Vision/CryptoKit được không | Build `.ipa` "hello + fetch screenshots" ngay ở task đầu | Tìm workaround trên issue tracker của xtool |
| R3 | Tốc độ và bộ nhớ với thư viện lớn (≥ 2.000 ảnh) | Đo ở Debug view | Phân tích dần theo lô, dùng ảnh thu nhỏ (~1024px) cho OCR |
| R4 | Ảnh đang ở iCloud (chế độ tối ưu dung lượng), không có bản gốc trên máy | Đếm số ảnh không tải được khi `isNetworkAccessAllowed = false` | Dùng thumbnail cục bộ cho OCR, bỏ qua SHA-256 (chỉ dùng FeaturePrint) |
| R5 | Ngưỡng gần trùng T gây xoá nhầm | Vẽ histogram khoảng cách trên bộ ảnh thật | Gần trùng luôn ở chế độ `review`, không preselect |

## Boundaries
- **Always:**
  - Chỉ xoá ảnh khi người dùng đã chọn và đã qua hộp thoại xác nhận của iOS.
  - Mỗi đề xuất xoá hiển thị lý do.
  - Biên lai không bao giờ được chọn sẵn để xoá.
  - Chạy `swift test` cho Core trước khi commit.
  - Cập nhật SPEC khi scope hoặc ngưỡng thay đổi.
- **Ask first:**
  - Thêm dependency bên thứ ba.
  - Thêm bất kỳ code mạng hoặc analytics nào.
  - Đổi cách xoá hoặc cách chọn sẵn.
  - Nâng iOS tối thiểu.
  - Di chuyển hoặc xoá các file `deep-dive-*.md`.
  - Init git, push lên remote.
- **Never:**
  - Tự xoá ảnh khi người dùng chưa xác nhận.
  - Gửi ảnh hoặc text OCR ra khỏi máy.
  - Lưu text OCR ngoài sandbox của app.
  - Dùng private API.
  - Commit Apple ID, chứng chỉ hoặc provisioning profile.
  - Tắt hoặc xoá test đang fail mà không được duyệt.

## Success Criteria
**POC xong khi:**
1. `xtool dev build --ipa` tạo được `.ipa`. Sau khi sideload, app chạy được trên iPhone iOS 17+ và liệt kê đúng số ảnh chụp màn hình bằng với album hệ thống.
2. `swift test` trong `ShotCleanCore` pass, gồm ≥ 30 fixture.
3. Trên bộ ≥ 100 ảnh chụp màn hình thật đã đánh nhãn tay:
   - Precision của đề xuất **delete** ≥ **95%**.
   - **0** biên lai bị đề xuất xoá.
   - Precision của trùng hoàn toàn đạt **100%**.
4. Xoá hàng loạt chỉ hiện **1** hộp thoại xác nhận cho cả lô. Ảnh đã xoá xuất hiện trong "Đã xoá gần đây".
5. Đã ghi kết quả R1–R5 vào SPEC, gồm số đo tốc độ phân tích trên máy test.
6. `grep -rE "URLSession|URLRequest|import Network" ShotClean/Sources` không ra kết quả nào (không có code mạng).

**MVP xong khi:** US1–US8 chạy được. Tác giả dùng app 2 tuần liền, không gặp lần xoá nhầm nào, và quét lại tăng dần (chỉ ảnh mới) mất < 10 giây với ≤ 50 ảnh mới.

## Open Questions
1. **Biên lai chuyển khoản:** luôn giữ, hay cho phép đề xuất xoá biên lai đã cũ (ví dụ > 12 tháng) trong một nhóm riêng có cảnh báo?
2. **QR "không cần thiết":** định nghĩa "chủ yếu là QR, cũ hơn 7 ngày" đã đúng ý chưa? Có loại QR nào cần giữ không, ví dụ QR nhận tiền của chính bạn hoặc QR wifi?
3. **Trùng hoàn toàn:** giữ ảnh **cũ nhất** hay **mới nhất**?
4. **Ân hạn:** vé hết hạn sau 1 ngày, đơn hàng sau 30 ngày. Hai mốc này có hợp không?
5. **Máy test:** dòng iPhone và phiên bản iOS nào? Cần biết để đặt mục tiêu tốc độ, ví dụ ≤ 10 phút cho 1.000 ảnh.
6. **Git:** có init repo tại `D:\DuAnMa\Clean` ngay không? Có remote nào không?
