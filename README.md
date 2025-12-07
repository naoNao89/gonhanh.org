# GoNhanh

[![CI](https://github.com/khaphanspace/gonhanh.org/actions/workflows/ci.yml/badge.svg)](https://github.com/khaphanspace/gonhanh.org/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

Bộ gõ tiếng Việt cho macOS. Viết bằng Rust + SwiftUI.

## Về dự án

Một bộ gõ tiếng Việt đơn giản:

- Chỉ Unicode, không hỗ trợ bảng mã cũ (TCVN3, VNI Windows, CP 1258)
- Chỉ gõ tiếng Việt, không chuyển mã, không macro
- Engine dựa trên ngữ âm học, không phải bảng tra cứu
- UI native (SwiftUI), không dùng Qt hay Electron

Nếu cần chuyển mã hoặc bảng mã cũ, dùng [UniKey](https://www.unikey.org/), [EVKey](https://evkeyvn.com/), hoặc [OpenKey](https://github.com/tuyenvm/OpenKey).

## Ba Không

- 🚫 **Không thu phí** — Miễn phí, không có bản premium
- 🚫 **Không quảng cáo** — Không popup, không banner
- 🚫 **Không theo dõi** — Offline hoàn toàn, không gửi dữ liệu đi đâu

## Cam kết

- ✅ **Duy trì lâu dài** — Ít nhất đến 2030. Tôi dùng hàng ngày nên sẽ fix bug.
- ✅ **Phản hồi nhanh** — Issues/PRs được xem trong 48 giờ.
- ✅ **Ổn định** — Không breaking changes ở minor versions. Config được giữ nguyên qua các bản cập nhật.

## Cách hoạt động

Engine dựa trên ngữ âm học tiếng Việt thay vì bảng tra cứu:

```
Âm tiết = [Phụ âm đầu] + [Âm đệm] + Nguyên âm chính + [Âm cuối] + Thanh điệu
```

Thuật toán đặt dấu theo quy tắc ngữ âm. Hỗ trợ cả kiểu cũ (`hoà`) và kiểu mới (`hòa`).

Chi tiết: [docs/vietnamese-language-system.md](docs/vietnamese-language-system.md)

## Kiến trúc

```
┌─────────────────────────────────┐
│     Platform UI (Swift/WPF)    │
└───────────────┬─────────────────┘
                │ FFI
┌───────────────▼─────────────────┐
│         Rust Core Engine        │
└─────────────────────────────────┘
```

- macOS: SwiftUI (done)
- Windows: WPF (planned)

## So sánh

|  | GoNhanh | OpenKey | UniKey | EVKey |
|---|:---:|:---:|:---:|:---:|
| Năm | 2025 | 2019 | 2000 | 2018 |
| Miễn phí | ✅ | ✅ | ✅ | ✅ |
| Open source | ✅ | ✅ | ⚠️ | ✅ |
| Chỉ Unicode | ✅ | ❌ | ❌ | ❌ |
| macOS native | SwiftUI | Obj-C | Qt | Qt |
| Engine | Rust | C++ | C++ | C++ |

Nếu cần chuyển mã hay dùng bảng mã cũ, dùng UniKey/EVKey/OpenKey.

## Cài đặt

```bash
git clone https://github.com/khaphanspace/gonhanh.org
cd gonhanh.org
make build
cp -r platforms/macos/build/Release/GoNhanh.app /Applications/
```

Lần đầu chạy cần cấp quyền Accessibility trong System Settings.

## Phát triển

```bash
make test    # 99 tests
make build   # Build tất cả
make clean   # Xóa build artifacts
```

Xem thêm: [docs/development.md](docs/development.md) · [docs/architecture.md](docs/architecture.md)

## Roadmap

| Version | Khi nào | Gì |
|---------|---------|-----|
| 0.1 | Q1 2025 | macOS beta |
| 0.2 | Q2 2025 | Stable, auto-update |
| 0.3 | Q3 2025 | Windows |
| 1.0 | Q4 2025 | Production |

## Credits

- [UniKey](https://www.unikey.org/)
- [OpenKey](https://github.com/tuyenvm/OpenKey)
- [EVKey](https://evkeyvn.com/)

## License

[GPL-3.0-or-later](LICENSE)
