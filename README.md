# ShotClean

iOS 17+ app dọn ảnh chụp màn hình, phân loại 100% trên máy (OCR, QR, ảnh trùng, vé/đơn hàng hết hạn), luôn giữ biên lai chuyển khoản.
Spec: [SPEC.md](SPEC.md) · UI: [UI-SPEC.md](UI-SPEC.md) · Toolchain: [docs/toolchain.md](docs/toolchain.md)

## Build (WSL, không cần Mac)
```bash
cd ShotClean && xtool dev build --ipa        # → ShotClean/xtool/ShotClean.ipa (chưa ký)
cd ShotClean/Packages/ShotCleanCore && swift test   # 92 tests
```
Ký và cài bằng Sideloadly (Windows).

## Trạng thái (2026-10-15)
- Core: 92/92 test pass trên Linux. Trên 41 fixture, đề xuất xoá đúng 100%, không biên lai nào bị đề xuất xoá.
- App: build `.ipa` thành công với iPhoneOS 27.0 SDK (Xcode 27 qua xtool 1.22.2), 0 warning, binary arm64, MinimumOSVersion 17.0.
- Chưa làm: chạy thử trên iPhone thật và đo precision trên ≥ 100 ảnh thật (tiêu chí 1 phần runtime và tiêu chí 3 trong SPEC).
