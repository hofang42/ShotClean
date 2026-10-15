# Plan: ShotClean POC

> Nguồn: [SPEC.md](../SPEC.md), [UI-SPEC.md](../UI-SPEC.md). Cập nhật: 2026-10-15.

## Các mặc định đã chốt (từ Open Questions của SPEC)
1. Biên lai chuyển khoản: **luôn giữ**, không có nhóm nào đề xuất xoá biên lai.
2. QR không cần thiết: diện tích QR ≥ 15% ảnh, ảnh cũ hơn 7 ngày, và không phải biên lai.
3. Trùng hoàn toàn: **giữ ảnh cũ nhất** (đổi được trong Settings ở MVP).
4. Ân hạn: vé 1 ngày, đơn hàng 30 ngày.
5. Máy test: chưa biết. POC chỉ đo và ghi lại, chưa đặt mục tiêu tốc độ.
6. Git: repo local, remote `hofang42/ShotClean`, commit sau mỗi role.

## Phân vai (mỗi agent làm đúng 1 việc, chạy tuần tự)
| # | Role | Việc duy nhất | Phụ thuộc | Đầu ra |
|---|---|---|---|---|
| R1 | toolchain-engineer | Cài Swift + xtool + deps vào WSL Ubuntu, ghi lại kết quả | — | `docs/toolchain.md` |
| R2 | core-engineer | Package `ShotCleanCore` (models, normalizer, date parser, rules, clustering, aggregation), làm theo TDD | R1 | `ShotClean/Packages/ShotCleanCore/**` |
| R3 | test-engineer | Thêm fixture OCR ẩn danh (≥ 30) và test biên cho Core. **Không sửa code Core**: nếu thấy bug thì ghi vào `tasks/bugs.md` | R2 | `Tests/**/Fixtures`, test mới |
| R4 | platform-engineer | Project xtool (Package.swift, xtool.yml, Info.plist), tầng PhotoKit + Vision + `AppModel` | R2 | `ShotClean/Sources/ShotClean/{App,Library,Analysis}/**` |
| R5 | ui-engineer | Các màn SwiftUI S1–S8 + Debug theo UI-SPEC. Chỉ dùng `AppModel` | R4 | `ShotClean/Sources/ShotClean/Views/**` |
| R6 | code-reviewer | Review 5 trục, ghi findings vào `tasks/review.md`. **Không sửa code** | R5 | `tasks/review.md` |
| R7 | fixer | Sửa các finding Critical/Important trong review.md và bugs.md | R6 | sửa có ghi nguồn finding |

Lead (session chính) điều phối, chạy verify sau mỗi role, commit và push.

## Hợp đồng interface (các role phải tuân thủ, đổi thì báo lead)

### ShotCleanCore (Foundation only, Swift 6, Sendable)
```swift
public struct PixelSize: Sendable, Codable, Hashable { public let width: Int; public let height: Int }

public struct ScreenshotFeatures: Sendable, Codable, Equatable {
    public let id: String            // PHAsset.localIdentifier
    public let createdAt: Date
    public let pixelSize: PixelSize
    public let fileSize: Int64?      // bytes, nil nếu không biết
    public let text: String          // OCR thô
    public let qrAreaRatio: Double   // 0...1
    public let sha256: String?
}

public enum Category: String, Sendable, Codable, CaseIterable {
    case transferReceipt, exactDuplicate, expiredTicket, expiredOrder, qrCode, nearDuplicate, other
}

public struct Verdict: Sendable, Equatable {
    public enum Suggestion: String, Sendable, Equatable { case delete, keep, review, none }
    public let category: Category
    public let suggestion: Suggestion
    public let reason: String        // tiếng Việt
}

public struct Thresholds: Sendable { /* qrMinArea 0.15, qrMinAgeDays 7, ticketGraceDays 1,
    orderMaxAgeDays 30, nearDupMaxDistance (Float, mặc định 0.35 – tinh chỉnh ở POC),
    nearDupMaxGap 600s */ public static let `default`: Thresholds }

public enum TextNormalizer { public static func fold(_ s: String) -> String }  // lowercase, bỏ dấu, đ→d, gộp khoảng trắng
public enum DateExtractor { public static func dates(in text: String, reference: Date, calendar: Calendar) -> [Date] }

/// Classifier cho từng ảnh (không gồm nhóm trùng/gần trùng)
public struct ScreenshotClassifier: Sendable {
    public init(thresholds: Thresholds = .default)
    public func classify(_ f: ScreenshotFeatures, now: Date) -> Verdict
}

/// Gom cụm trên toàn thư viện
public struct DuplicateClusterer: Sendable {
    /// exact: cùng sha256 (không nil). near: distance < ngưỡng VÀ |Δt| ≤ maxGap, ngoại trừ ảnh đã nằm trong exact.
    public func clusters(features: [ScreenshotFeatures],
                         distance: (String, String) -> Float?) -> [Cluster]
}
public struct Cluster: Sendable, Equatable {
    public enum Kind: String, Sendable { case exact, near }
    public let kind: Kind
    public let memberIDs: [String]   // sắp theo createdAt tăng dần
    public let keeperID: String      // exact: ảnh cũ nhất · near: ảnh có pixel lớn nhất, hoà thì ảnh cũ nhất
}

/// Kết hợp tất cả. Ưu tiên: transferReceipt > exactDuplicate > expiredTicket/expiredOrder > qrCode > nearDuplicate > other
public struct LibraryAnalyzer: Sendable {
    public init(thresholds: Thresholds = .default)
    public func analyze(_ features: [ScreenshotFeatures],
                        distance: (String, String) -> Float?, now: Date) -> AnalysisResult
}
public struct AnalysisResult: Sendable {
    public let verdicts: [String: Verdict]        // id → verdict cuối cùng
    public let clusters: [Cluster]
    public func ids(in category: Category) -> [String]
    public func preselectedForDeletion() -> Set<String>   // chỉ suggestion == .delete (không bao giờ gồm receipt/near)
    public func reclaimableBytes(_ ids: Set<String>, sizes: [String: Int64]) -> Int64
}
```
Quy tắc: ảnh exact-dup là keeper → không đề xuất xoá vì trùng (vẫn có thể rơi vào nhóm khác). Receipt luôn là `.keep`, kể cả khi trùng.

### App layer (R4 cung cấp cho R5)
```swift
@MainActor @Observable final class AppModel {
    enum Phase { case needsOnboarding, needsPermission, denied, scanning(done: Int, total: Int), ready }
    var phase: Phase
    var isLimitedAccess: Bool
    var result: AnalysisResult?
    var sizes: [String: Int64]
    var selection: Set<String>                  // ID đang chọn để xoá
    var swipeQueue: [String]                    // hàng chờ vuốt
    func start() async                          // onboarding xong → xin quyền → quét
    func requestPermission() async
    func rescan(full: Bool) async
    func cancelScan()
    func delete(_ ids: Set<String>) async throws -> Int   // trả về số ảnh đã xoá, hiện confirm của iOS
    func thumbnail(for id: String, size: CGSize) async -> UIImage?
    func features(for id: String) -> ScreenshotFeatures?   // cho màn Debug
}
```

## Verify sau mỗi role (lead chạy)
- R2, R3: `cd ShotClean/Packages/ShotCleanCore && swift test` trong WSL phải pass.
- R4, R5: `grep -rE "URLSession|URLRequest|import Network" ShotClean/Sources` phải rỗng. Build `.ipa` chỉ chạy được khi người dùng đã `xtool sdk install`. Nếu chưa có SDK, chỉ kiểm tra cấu trúc, ghi rõ là **chưa build thử**.
- R6: review.md có mức độ cho từng finding.
- R7: test vẫn pass, mọi finding Critical đã được xử lý.
