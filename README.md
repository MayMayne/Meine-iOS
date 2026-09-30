# Meine

Ứng dụng giải trí native cho iOS 18. Đọc truyện chữ, đọc truyện tranh, nghe nhạc, xem phim và shorts. Icon trước, chữ sau. Nguồn do bạn nạp. Không khóa API trong app.

Bundle ID: `app.meine.ios`.

## Có gì trong máy

- Nguồn mẫu **Meine** mở được ngay: truyện chữ hai chương, manga tám trang vẽ, nhạc tổng hợp kèm lời, phim và shorts.
- Tiến trình tự lưu. Phim xem quá 90% thì lần sau phát lại từ đầu. Xem hơn 10 giây thì tiếp tục, có dòng báo thời gian.
- Cài đặt chỉ bốn mục: nguồn, AI Gateway, bộ nhớ đệm, sao lưu `.meinebackup`.
- AI là BYOK. Lỗi 429, 401 hoặc localhost chết thì dừng và hiện lỗi. Không tự đổi nhà cung cấp.
- Nguồn khóa bằng mật khẩu trên máy. Không có OAuth Google Drive cá nhân — chỉ Folder ID công khai khi bạn tự nạp nguồn.

## Cài IPA chưa ký

Repo công khai, runner `macos-latest`.

1. Mở [Actions](https://github.com/MayMayne/Meine-iOS/actions/workflows/build-unsigned-ipa.yml).
2. **Run workflow** trên nhánh `main`.
3. Tải artifact `unsigned-ipa`.

Cài:

- TrollStore: cài thẳng file IPA, không cần ký lại.
- Sideloadly, SideStore hoặc AltStore: công cụ ký lại lúc cài.
- Jailbreak kèm AppSync Unified: cài như gói thường.

IPA này **không** cài được bằng Finder, Apple Configurator hay Device Management thông thường.

Codemagic dùng `codemagic.yaml` trên Mac mini M2, Xcode mới nhất, cũng đóng gói IPA chưa ký. Không cần chứng chỉ.

## Mở trong Xcode

```bash
python3 scripts/gen_xcodeproj.py
open Meine.xcodeproj
```

Scheme `Meine`. Deployment target iOS 18. Không cần team ký nếu bạn archive với `CODE_SIGNING_ALLOWED=NO`.

## Nạp nguồn của bạn

JSON có `id`, `name`, `upstreams` và `catalog`. Dán, chọn tệp, hoặc tải từ URL trong mục nguồn. Meine không kèm site. Scraper chỉ chạy trên luật bạn ghi trong nguồn.

Ví dụ tối thiểu:

```json
{
  "id": "tu-nguon",
  "name": "Kệ nhà",
  "version": "1",
  "passwordProtected": false,
  "upstreams": [{ "id": "local", "kind": "local", "config": {} }],
  "mirrors": [],
  "catalog": []
}
```

## Việc cố ý chưa nhét binary

FFmpeg, Metal shader riêng và libarchive không nằm trong IPA này. Phim đi qua AVFoundation. Manga không có URL thì vẽ trang mẫu. EPUB hỏng thì bộ tách chương regex vẫn chạy trên chữ thường. Face ID có chuỗi quyền; mở khóa nguồn trong bản này là mật khẩu.
