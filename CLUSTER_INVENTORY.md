# 🌐 Toàn Bộ Danh Sách Máy Chủ GPU Thuê Trên Vast.ai (Lịch Sử & Hiện Tại)

Tài liệu này ghi nhận đầy đủ danh bạ toàn bộ các máy chủ GPU mà hệ thống đã thuê từ trước đến nay (Máy A ➔ I), phục vụ cụm suy luận **SGLang Qwen 3.8-27B DFlash2 Golden Runtime**.

---

## 📊 Bảng Tổng Hợp Chi Tiết Toàn Bộ Các Máy (Bao Gồm Phí Duy Trì Khi Tắt)

| Tên Máy | Vast ID | Cấu hình GPU | CPU | RAM | NVMe Disk | Lệnh Kết Nối SSH Chuẩn | Phí Khi BẬT (Running) | 🔒 Phí DUY TRÌ Khi TẮT (Storage) | Vị Trí | Trạng Thái |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Máy A** | `48270104` | 2x RTX 3090 | AMD EPYC | | 32 GB | | $0.260/hr | $0.015/hr | US | 🗑️ Đã hủy |
| **Máy B** | `48270992` | 2x RTX 3090 | AMD EPYC | | 32 GB | | $0.265/hr | $0.015/hr | US | 🗑️ Đã hủy |
| **Máy C** | `48283311` | 2x RTX 3090 | AMD EPYC | 128 GB | 32 GB | | $0.270/hr | $0.015/hr | US | 🗑️ Đã hủy |
| **Máy D** | `48333887` | 2x RTX 3090 | AMD EPYC 7R32 (96T) | 128 GB | 45 GB | `ssh -p 53040 root@199.68.217.31`<br>`ssh -p 13886 root@ssh7.vast.ai` | **$0.2650/hr** | **$0.0250/hr** (~$18.00/tháng) | California, US | 💤 Standby |
| **Máy E** | `48394592` | 2x RTX 3090 | AMD EPYC 7502 (64T) | 128 GB | 32 GB | `ssh -p 34593 root@ssh3.vast.ai` | $0.2690/hr | $0.0150/hr | California, US | 🗑️ Đã hủy |
| **Máy F** | `48423230` | 2x RTX 3090 | Intel Xeon E5-2686 v4 (72T) | **193 GB** | 32 GB | `ssh -p 10134 root@80.251.216.116`<br>`ssh -p 23231 root@ssh4.vast.ai` | **$0.2729/hr** | **$0.0089/hr** (~$6.40/tháng) | California, US | 🟢 Live (Đang tải Model) |
| **Máy G** | `48423380` | 2x RTX 3090 | AMD Ryzen 5 5500 (12T) | 64 GB | 32 GB | `ssh -p 31027 root@65.95.12.163`<br>`ssh -p 23381 root@ssh6.vast.ai` | **$0.2296/hr** | **$0.0163/hr** (~$11.73/tháng) | Quebec, CA | 🟢 Live (Primary Leader) |
| **Máy H** | `48423711` | 2x RTX 3090 | AMD EPYC 7742 (128T) | **257 GB** | 32 GB | `ssh -p 55122 root@61.71.33.195`<br>`ssh -p 23711 root@ssh8.vast.ai` | **$0.2782/hr** | **$0.0089/hr** (~$6.40/tháng) | Taiwan, TW | 🟢 Live (Đang tải Model) |
| **Máy I (Mới)** | `48424397` | 2x RTX 3090 | **Ryzen Threadripper PRO 3955WX** | **256 GB** | 32 GB | `ssh -p 24396 root@ssh3.vast.ai` | **$0.2696/hr** | **$0.0030/hr** 🌟 (~$2.13/tháng) | BC, Canada | ⏳ Loading Docker |

---

## 🔍 Phân Tích Phí Duy Trì (Storage Cost) Khi Tắt Máy:

Khi máy ở trạng thái **STOP / TẮT**, Vast.ai không tính tiền GPU mà chỉ tính tiền **Lưu trữ ổ cứng (Disk Storage Cost)**:

1. 🌟 **Máy I (`48424397` - Threadripper PRO 3955WX / 256GB RAM)**:
   * Phí duy trì khi TẮT: **`$0.0030/giờ`** (👉 **Chỉ ~$2.13 / tháng**). 
   * **Cực kỳ thích hợp làm máy Failover lâu dài** vì tiền lưu trữ gần như bằng 0!
2. 🥈 **Máy H (`48423711`) & Máy F (`48423230`)**:
   * Phí duy trì khi TẮT: **`$0.0089/giờ`** (~$6.40 / tháng).
3. 🥉 **Máy G (`48423380`)**:
   * Phí duy trì khi TẮT: **`$0.0163/giờ`** (~$11.73 / tháng). Phí khi BẬT rẻ nhất ($0.2296/hr) ➔ Phù hợp làm máy chạy chính thường xuyên.
4. **Máy D (`48333887`)**:
   * Phí duy trì khi TẮT: **`$0.0250/giờ`** (~$18.00 / tháng do ổ cứng 45GB với đơn giá storage $0.40/GB/tháng).

---

## 🤖 Khả Năng Tự Thuê Máy Tự Động Qua Vast API:
Vast.ai API hỗ trợ **100% tự động tìm kiếm và thuê máy**:
* **Tìm kiếm theo tiêu chí (Search Offers)**: `POST https://console.vast.ai/api/v1/bundles/` lọc theo phí Storage thấp nhất, GPU 2x 3090, RAM $\ge 64$GB, độ tin cậy $\ge 0.98$.
* **Thuê tự động (Rent Ask)**: `PUT https://console.vast.ai/api/v1/asks/{ask_id}/` kèm theo Template Golden Runtime (`596334`) và script bootstrap tự chạy!
