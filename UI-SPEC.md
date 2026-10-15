# UI Spec: ShotClean

> Trạng thái: **DRAFT, chờ duyệt** · Đi kèm [SPEC.md](SPEC.md) · Mockup trực quan: [ui-mockup.html](ui-mockup.html)
> Phạm vi: màn hình cho POC/MVP (iOS 17+, SwiftUI). Phần paywall chỉ phác thảo cho v1.

## 1. Nguyên tắc thiết kế
1. **Minh bạch trước, đẹp sau.** Mỗi ảnh được đề xuất xoá luôn có **lý do** hiển thị ngay trên thumbnail, ví dụ "Vé ngày 12/09 đã qua" hoặc "Giống hệt 100%".
2. **An toàn là mặc định.** Biên lai có card riêng gắn khiên bảo vệ. Ảnh gần trùng không bao giờ được chọn sẵn. Thao tác vuốt chỉ **xếp vào hàng chờ**, không xoá thật. Xoá thật chỉ xảy ra sau **1 hộp thoại xác nhận của iOS**.
3. **Không dark pattern.**
   - Không paywall trước khi người dùng thấy giá trị.
   - Không cảnh báo giả kiểu "máy sắp đầy", không đồng hồ đếm ngược.
   - Không trial tự chuyển sang subscription.
   - Thông điệp "Mua 1 lần, không subscription" là điểm bán hàng.
4. **Privacy hiển thị rõ.** Badge "Xử lý trên máy · Không tải ảnh lên" xuất hiện ở onboarding, màn quét và Cài đặt.
5. **Native, không lạ mắt.** Theo Apple HIG:
   - Dùng font hệ thống với Dynamic Type, SF Symbols và semantic colors.
   - Dark mode hiển thị đẹp ngay từ đầu.
   - Kiểm tra dấu tiếng Việt không bị cắt và chuỗi dài thêm 30% vẫn vừa.

## 2. Luồng màn hình
```
[S1 Onboarding] → [S2 Xin quyền] ──denied──→ [E1 Không có quyền → Mở Cài đặt]
                        │ authorized / limited
                        ▼
                  [S3 Đang quét] → [S4 Tổng quan] ─┬→ [S5 Lưới theo nhóm] ─→ [S8 Xác nhận & Kết quả]
                                         │          ├→ [S6 Duyệt cụm trùng] ─→ [S8]
                                         │          └→ [S7 Chế độ vuốt]      ─→ [S8]
                                         └→ [S9 Cài đặt]          (v1: [S10 Mua 1 lần])
```
Điều hướng dùng `NavigationStack` với một màn gốc là **Tổng quan**. Màn quét là trạng thái của Tổng quan, không phải màn riêng: sau lần đầu, kết quả cache hiện ngay và việc quét ảnh mới chạy nền với progress nhỏ ở đầu màn.

## 3. Design tokens
| Token | Light | Dark | Dùng cho |
|---|---|---|---|
| `accent` | `#2F6BFF` | `#5B8CFF` | Nút chính, tiến trình, link |
| `destructive` | system `.red` | system `.red` | Chỉ cho xoá |
| `keep` | `#1E9E62` | `#34C77B` | Giữ lại, biên lai |
| `bg` / `card` | `systemGroupedBackground` / `secondarySystemGroupedBackground` | tương tự | Nền, card nội dung (đặc, không dùng glass) |
| Màu theo nhóm | `exactDuplicate` blue · `nearDuplicate` teal · `qrCode` purple · `expiredTicket` orange · `expiredOrder` amber · `transferReceipt` green | bản sáng hơn trong dark mode | Icon, chip, thanh trong biểu đồ |

- **Typography:** chữ thường dùng text styles hệ thống (`.largeTitle` → `.caption2`). Chỉ **số lớn** (GB giải phóng, bộ đếm) dùng `.fontDesign(.rounded)` + `.monospacedDigit()`.
- **Bo góc:** card 16, thumbnail 10, nút 12. **Khoảng cách:** 4/8/12/16/24.
- **Icon nhóm (SF Symbols):** `doc.on.doc` (trùng), `square.on.square.dashed` (gần trùng), `qrcode`, `ticket`, `shippingbox`, `checkmark.shield` (biên lai), `trash`.
- **Màu không đứng một mình.** Luôn có icon hoặc chữ đi kèm, vì người mù màu không phân biệt được chỉ bằng màu.

## 4. Màn hình

### S1 · Onboarding (1 màn)
- Phía trên là minh hoạ (stack thumbnail + icon khiên). Tiêu đề: **"Dọn ảnh chụp màn hình, không xoá nhầm."**
- 3 dòng lợi ích có icon:
  - "Chỉ quét ảnh chụp màn hình"
  - "Xử lý 100% trên máy"
  - "Biên lai luôn được giữ lại"
- Nút chính **"Bắt đầu"**. Dòng nhỏ: "Mua 1 lần · Không subscription" (chỉ hiện từ v1).

### S2 · Xin quyền (priming trước prompt hệ thống)
- Giải thích lý do cần **toàn quyền truy cập thư viện**: để quét toàn bộ ảnh chụp màn hình và xoá theo lựa chọn của người dùng.
- Nút **"Cho phép truy cập"** → gọi `requestAuthorization(for: .readWrite)`.
- **Trạng thái `.limited`:** banner ở Tổng quan ghi "Chỉ đang quét N ảnh bạn đã chọn", kèm nút "Chọn thêm" (`presentLimitedLibraryPicker`).
- **E1 `.denied`:** empty state với nút **"Mở Cài đặt"** (`UIApplication.openSettingsURLString`).

### S3 · Đang quét
- **Vòng tiến trình lớn**, số đếm `1.240 / 3.800` dùng `.contentTransition(.numericText())`.
- **Chip nhóm hiện dần** khi tìm thấy, ví dụ: "Trùng 32", "QR 18", "Vé 7"...
- Badge privacy. Nút **"Huỷ"**.
- Khi xong: haptic `.sensoryFeedback(.success)`, chuyển sang Tổng quan bằng animation.

### S4 · Tổng quan (màn gốc)
- **Hero card:**
  - Hiển thị **"Có thể giải phóng ~1,2 GB"**, số dạng rounded.
  - Dưới đó là **1 thanh xếp chồng (Swift Charts)** cho biết dung lượng theo từng nhóm, có accessibility label.
  - Dòng phụ: "từ 412 ảnh / 3.800 ảnh chụp màn hình".
- **Danh sách card nhóm.** Mỗi card gồm icon màu, tên nhóm, số ảnh, dung lượng, 1 dòng lý do và chevron:
  - Trùng hoàn toàn · QR không cần thiết · Vé hết hạn · Đơn hàng hết hạn · Gần trùng (badge "Cần bạn xem").
- **Card "Được bảo vệ"** tách riêng ở cuối: biên lai chuyển khoản, icon khiên xanh, nội dung "128 ảnh · luôn giữ lại".
- **Thanh nổi dưới cùng:**
  - Nút chính **"Dọn nhanh 318 ảnh"**. Mục "nhanh" chỉ gồm các nhóm được chọn sẵn để xoá, **không** gồm gần trùng.
  - Nút phụ **"Vuốt để duyệt"**.
- Thanh nổi dùng **glass** trên iOS 26, `.ultraThinMaterial` trên iOS 17–25.

### S5 · Lưới theo nhóm
- `LazyVGrid(.adaptive(minimum: 104))`, khoảng 3 cột trên iPhone.
- Mỗi thumbnail có **badge lý do** ở dưới (1 dòng, cắt bớt nếu dài) và vòng chọn ở góc trên phải.
- Toolbar: "Chọn tất cả / Bỏ chọn", menu sắp xếp (cũ nhất, lớn nhất).
- Chạm vào ảnh để xem toàn màn hình, có lý do đầy đủ và text OCR đã nhận ra (chỉ ở bản debug/POC).
- **Thanh dưới cố định:** "Xoá 24 ảnh · 180 MB" (màu destructive). Nút bị vô hiệu khi chưa chọn ảnh nào.

### S6 · Duyệt cụm trùng / gần trùng
- Mỗi cụm là 1 hàng cuộn ngang. Ảnh **được giữ** có viền `keep` + nhãn **"Giữ"**, kèm lý do ("Cũ nhất" / "Nét nhất").
- Chạm vào ảnh khác để đổi ảnh giữ. Nút **"So sánh"** mở 2 ảnh cạnh nhau, pinch-zoom đồng bộ.
- Nhãn khác nhau: **"Giống hệt"** (trùng hoàn toàn) và **"Gần giống"** (gần trùng). Với gần trùng, mặc định không chọn ảnh nào để xoá.

### S7 · Chế độ vuốt
- Stack card ảnh lớn ở giữa, lý do và ngày hiển thị dưới ảnh.
- **Vuốt trái = cho vào hàng chờ xoá** (overlay đỏ "Xoá"), **vuốt phải = giữ** (overlay xanh "Giữ").
- Luôn có **nút Giữ / Xoá / Hoàn tác** cho người không dùng cử chỉ, cộng VoiceOver custom actions. Tôn trọng Reduce Motion.
- Đầu màn có bộ đếm "Hàng chờ: 37 ảnh · 210 MB". Nút **"Xong"** đi tới S8.

### S8 · Xác nhận & kết quả
1. **Sheet tóm tắt** (không phải alert tự chế): "Xoá 412 ảnh · ~1,2 GB · Ảnh sẽ nằm trong *Đã xoá gần đây* 30 ngày". Nút **"Xoá"**.
2. Sau đó là **hộp thoại xác nhận của iOS** từ `deleteAssets`. Không chồng thêm alert nào khác.
3. **Màn kết quả:**
   - Số GB đếm lên + checkmark có `symbolEffect` + haptic success.
   - Câu trung thực: "Dung lượng được trả lại hoàn toàn sau khi bạn dọn *Đã xoá gần đây*", kèm hướng dẫn 1 dòng.
   - Nút "Về Tổng quan".
   - (v1) Hỏi đánh giá App Store **chỉ sau lần dọn thành công thứ 2**.

### S9 · Cài đặt
- **Nhóm "Quy tắc":**
  - Ngưỡng QR cũ hơn **N ngày** (stepper, mặc định 7).
  - Ân hạn vé (1 ngày) và đơn hàng (30 ngày).
  - Độ nhạy gần trùng (Thấp / Vừa / Cao).
  - Giữ ảnh **cũ nhất / mới nhất** khi trùng.
- **Nhóm "Bảo vệ":** công tắc "Luôn giữ biên lai" (bật, chưa cho tắt ở MVP).
- **Nhóm "Quyền riêng tư":** giải thích ngắn, link "Quyền truy cập Ảnh".
- **Nhóm "Khác":** quét lại toàn bộ, xoá cache phân tích, phiên bản. (v1) Khôi phục giao dịch mua.

### S10 · Mua 1 lần (v1, phác thảo)
- Chỉ xuất hiện khi dùng vượt free tier, ví dụ sau 100 ảnh đã dọn. Không xuất hiện lúc onboarding.
- Giá đọc từ StoreKit (`Product.displayPrice`). Ghi rõ "Mua 1 lần, dùng mãi". Nút đóng hiển thị rõ ràng.

## 5. Component chính (SwiftUI)
| Component | Mô tả | Ghi chú triển khai |
|---|---|---|
| `CategoryCard` | icon + tên + count + size + reason + chevron | `NavigationLink`, `accessibilityElement(children: .combine)` |
| `ReclaimBar` | thanh xếp chồng dung lượng | Swift Charts `BarMark(stacking:)`, 1 hàng |
| `ThumbnailCell` | thumbnail + badge lý do + vòng chọn | `PHCachingImageManager`, ảnh khoảng 200px, `.task(id:)` |
| `FloatingActionBar` | thanh nút nổi đáy | `.safeAreaInset(edge: .bottom)` + `GlassOrMaterial` |
| `SwipeCard` | card kéo có overlay | `DragGesture` + `.sensoryFeedback`, có fallback nút |
| `ClusterRow` | cụm ngang chọn ảnh giữ | `ScrollView(.horizontal)` + `matchedGeometryEffect` cho nhãn "Giữ" |
| `PrivacyBadge` | "Xử lý trên máy" | dùng ở S1, S3, S9 |

**Helper glass, tương thích iOS 17:**
```swift
extension View {
    @ViewBuilder
    func glassOrMaterial(cornerRadius: CGFloat = 20) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
```
> `glassEffect` cần iOS 26 SDK. Xcode 27 `.xip` có SDK này, nên xtool compile được. Nhớ kiểm tra lúc build. Chỉ dùng glass cho **control nổi**, không dùng cho card nội dung, không chồng glass lên glass. Test thêm với Reduce Transparency.

## 6. Accessibility & bản địa hoá
- Hỗ trợ Dynamic Type đến `accessibility3`: lưới chuyển còn 2 cột, card chuyển sang layout dọc.
- VoiceOver đọc được lý do ("Vé hết hạn, ngày 12 tháng 9"). Ở chế độ vuốt có custom actions Giữ / Xoá.
- Mọi chuỗi đặt trong `Localizable.xcstrings`. Nếu xtool chưa xử lý được `.xcstrings` thì dùng `Localizable.strings` (cần kiểm tra ở POC). Ở MVP chỉ có `vi`, đến v1 thêm `en`.
- Định dạng số và ngày theo `Locale("vi_VN")`: `1.240`, `1,2 GB`, `12/09/2026`.

## 7. Skill AI dùng khi làm UI (đã research 2026-10-15)
| Skill | Vì sao | Cài cho Claude Code |
|---|---|---|
| **swiftui-pro** (Paul Hudson) | Bắt lỗi SwiftUI mà LLM hay mắc: API lỗi thời, state, navigation, accessibility. Phù hợp nhất cho code đúng và hiện đại | `/plugin marketplace add twostraws/SwiftUI-Agent-Skill` → `/plugin install swiftui-pro@swiftui-agent-skill` |
| **ui-ux-pro-max** | Đưa ra hướng thiết kế: palette, font pairing, style. Có stack SwiftUI. Rất phổ biến (~136k sao), nhưng lời khuyên khá chung chung kiểu web nên phải đối chiếu với HIG | `/plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill` → `/plugin install ui-ux-pro-max@ui-ux-pro-max-skill` (cần Python 3) |
| **Dimillian/Skills**: chỉ lấy `swiftui-ui-patterns`, `swiftui-liquid-glass` | Pattern cho màn hình và hiệu ứng glass. Glass chỉ có từ iOS 26 nên cần `#available` | Copy 2 thư mục vào `~/.claude/skills/` |

**Không dùng:**
- `frontend-design` và shadcn: chỉ dành cho web.
- Các phần cần Xcode, Instruments hoặc Simulator trong `swiftui-expert-skill` và `ios-debugger-agent`, vì không chạy được trên Linux.
- Chỉ nên cài **một** trong hai `swiftui-pro` / `swiftui-expert` vì chúng trùng nhau, cài cả hai tốn context.

**Đã cài (2026-10-15, scope user):**
- `swiftui-pro@swiftui-agent-skill`
- `ui-ux-pro-max@ui-ux-pro-max-skill`
- `~/.claude/skills/swiftui-ui-patterns`
- `~/.claude/skills/swiftui-liquid-glass`

Cách dùng khi viết UI:
- Dùng `swiftui-pro` + `swiftui-ui-patterns`.
- `ui-ux-pro-max` chỉ dùng để chọn hướng thẩm mỹ, phải đối chiếu với HIG.
- `swiftui-liquid-glass` chỉ dùng cho nhánh `#available(iOS 26, *)`.

## 8. Quyết định đã chốt (2026-10-15)
1. Màu accent: **`#2F6BFF`** (dark: `#5B8CFF`).
2. **Chế độ vuốt (S7) nằm trong POC.**
3. Tên hiển thị: **ShotClean** (tạm thời).
4. Đã cài các skill UI (xem mục 7).

## 9. Open Questions (UI)
1. Ở bản đầu có cần màn chi tiết ảnh hiển thị text OCR không? Đề xuất: **chỉ ở bản debug**.
