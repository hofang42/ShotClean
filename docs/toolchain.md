# Toolchain (WSL2 Ubuntu 26.04, user `hofang`)

## Đã cài (user-local, không cần sudo)
| Thành phần | Phiên bản | Đường dẫn |
|---|---|---|
| swiftly | 1.2.0 | `~/.local/share/swiftly` |
| Swift | 6.4.1 (build ubuntu26.04) | `~/.local/share/swiftly/toolchains/6.4.1` |
| Swift Testing | 6.4.1 (đã xác nhận `swift test` chạy PASS trên Linux) | đi kèm toolchain |
| xtool | AppImage (chạy được, không cần FUSE) | `~/.local/bin/xtool` |
| libncurses6 (extract từ .deb) | 6.6 | `~/.local/opt/ncurses6` + bản copy `libncurses.so.6` trong `toolchains/6.4.1/usr/lib/swift/linux/` |

Lưu ý: nếu `swiftly` cài lại/xóa toolchain 6.4.1 thì phải copy lại:
`cp ~/.local/opt/ncurses6/usr/lib/x86_64-linux-gnu/libncurses.so.6.6 ~/.local/share/swiftly/toolchains/6.4.1/usr/lib/swift/linux/libncurses.so.6`

## Kích hoạt PATH
`~/.profile` đã có: swiftly env.sh, `~/.local/bin` trên PATH, `LD_LIBRARY_PATH` trỏ tới ncurses6.
Dùng: `wsl.exe -e bash -lc 'swift test'` (login shell). Shell hiện tại: `. ~/.profile`.
`swiftly install` cũng tạo `D:\DuAnMa\Clean\.swift-version` (= 6.4.1) để ghim toolchain.

## Gói hệ thống còn thiếu (cần sudo, chạy 1 lần)
swift test/build đã chạy được mà không cần các gói này; swiftly khuyến nghị để dùng đầy đủ (Foundation networking, lldb, v.v.):

```
sudo apt-get install -y binutils-gold gnupg2 libcurl4-openssl-dev libpython3-dev libxml2-dev libncurses-dev libz3-dev pkg-config zlib1g-dev
```
(`libncurses-dev` cũng sẽ kéo `libncurses6`, thay cho bản extract thủ công.)

## Bước thủ công còn lại
1. Tải `Xcode.xip` từ Apple Developer (đăng nhập Apple trong trình duyệt).
2. Chạy trong WSL: `xtool sdk install /mnt/c/.../Xcode.xip` (đường dẫn tới file đã tải).
3. Sau đó `xtool setup` / `xtool auth` nếu cần ký và cài app lên iPhone.
