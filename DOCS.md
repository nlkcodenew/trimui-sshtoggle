# Trimui-SSHToggle — Tài liệu sử dụng (tiếng Việt)

## 1. App này là gì?

**SSH Toggle** là app siêu nhẹ cho máy TrimUI (Brick Pro và các máy chạy stock OS),
bật/tắt SSH chạy nền chỉ bằng **1 lần mở app**:

- **Mở lần 1** → bật SSH: dropbear nghe cổng LAN `2222` + reverse tunnel về VPS (cổng `22223`).
- **Mở lần 2** → tắt SSH: dừng dropbear, tunnel và keeper, dọn sạch tiến trình.

Không UI, không OTA, không setting rườm rà. Mở app xong màn hình nháy rồi về menu là bình thường.

## 2. Cài đặt

- Tải `trimui-sshtoggle-vX.Y.Z.zip` ở mục Releases trên GitHub, giải nén vào `/mnt/SDCARD/Apps/`
  sao cho có `/mnt/SDCARD/Apps/SSHToggle/launch.sh`.
- Hoặc chép tay cả thư mục `SSHToggle` vào `/mnt/SDCARD/Apps/`.

## 3. Cách dùng

1. Mở **SSH Toggle** trong menu Apps.
2. Nhìn vòng LED 2 cần joystick:
   - **Xanh lá nháy 3 lần** → SSH đã bật.
   - **Đỏ nháy 2 lần** → SSH đã tắt.
3. SSH từ xa: `ssh -p 22223 root@<địa-chỉ-VPS>`.
4. SSH trong LAN: `ssh -p 2222 root@<IP-của-máy>`.

Lần chạy đầu, app tự sinh host key Ed25519 (`data/dropbear_host_key`).

## 4. Tunnel VPS

- Dùng `dbclient -R 22223:localhost:2222`, tự thử lại mỗi 15 giây khi mất mạng, keepalive 120s.
- Key tunnel: tái dùng `tunnel_key` của TrimuiRemote nếu có
  (`/mnt/SDCARD/Apps/TrimuiRemote/data/tunnel_key`); nếu không, đặt key riêng
  vào `SSHToggle/data/tunnel_key`.
- Không có key → SSH LAN vẫn chạy, tunnel VPS không xác thực được.

## 5. Đừng chạy cùng TrimuiRemote

Hai app dùng chung cổng `2222` (LAN) và `22223` (tunnel VPS).
**Chỉ dùng một trong hai** tại một thời điểm.

## 6. LED phản hồi (quirk phần cứng)

- Dùng vòng LED 2 cần joystick: `/sys/class/leds/sunxi_led10` … `sunxi_led22`.
- **Quirk Brick Pro**: tên kênh `r`/`g` trong sysfs bị đảo so với màu đèn thật
  (ghi `g` thì đèn đỏ sáng). Code đã map lại trong `led_color()` để xanh = bật,
  đỏ = tắt đúng ý nghĩa.

## 7. Keeper chống deep-suspend

Khi bật, app chạm `/tmp/stay_alive` mỗi 30 giây để máy không vào deep-suspend
lúc idle → SSH luôn sẵn sàng khi tắt màn hình. Tắt app thì xóa file này.

## 8. Hỏi đáp

### Bấm nút nguồn tắt màn hình thì SSH có mất không?
**Có.** Nút nguồn cho máy vào suspend → WiFi tắt → SSH và tunnel đứt.
Mở màn hình lại → WiFi nối lại → vòng retry của app tự dựng lại tunnel sau
~15–30 giây, **không cần mở lại app**.
(Keeper chỉ ngăn máy *tự* ngủ khi idle, không cản được nút nguồn bấm tay.)

### App có tốn pin không?
- dropbear + dbclient lúc idle: tốn không đáng kể (vài MB RAM, CPU ~0%).
- Keeper (chạm file mỗi 30 giây): nhẹ.
- **Chi phí chính là hệ quả**: keeper giữ máy khỏi deep-suspend → máy ở trạng
  thái thức (dù tắt màn hình), WiFi duy trì → tốn pin hơn deep sleep rõ rệt,
  nhưng ít hơn nhiều so với mở màn hình dùng máy.
- Đây là đánh đổi cần thiết để SSH luôn sẵn sàng. Không cần SSH từ xa nữa
  → mở app tắt đi.

### Mất WiFi rồi có lại thì sao?
Vòng retry 15 giây tự nối lại tunnel, không cần động tay.

### Log ở đâu?
`data/toggle.log` trên thẻ (tự xoay, giữ 200 dòng cuối).

## 9. Cấu trúc thư mục

```
SSHToggle/
├── launch.sh        # launcher cho menu TrimUI
├── sshtoggle.sh     # toggle|on|off|status
├── config.json      # label + icon cho menu
├── background.png   # nền menu khi focus icon (launcher đọc key "background")
├── icon.png
├── VERSION
├── DOCS.md          # tài liệu này
├── bin/             # dropbear, dbclient, dropbearkey, dropbearconvert (static aarch64)
└── data/            # runtime: keys, pid, log (gitignored)
```

## 10. Sửa code

Không cần build — toàn bộ là shell script + binary static có sẵn.
Sửa `sshtoggle.sh` → chạy `sh -n sshtoggle.sh` kiểm tra cú pháp → chép lên máy là xong.
