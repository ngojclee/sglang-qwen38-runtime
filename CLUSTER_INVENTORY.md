# 🌐 Vast.ai GPU Cluster Inventory & Node Registry

Tài liệu này lưu trữ danh bạ toàn bộ các máy chủ GPU (Nodes) thuộc cụm suy luận **SGLang Qwen 3.8-27B DFlash2**, bao gồm thông số phần cứng, địa chỉ kết nối SSH, giá thuê và trạng thái vận hành.

---

## 📊 Bảng Tổng Hợp Danh Sách Nodes

| Mã Máy | Instance ID | Model GPU | VRAM | CPU | RAM | Disk | SSH Direct / Proxy | Giá $/hr | Vị trí | Trạng thái |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Máy F** | `48423380` | 2x RTX 3090 | 48 GB | AMD Ryzen 5 5500 (12T) | 64 GB | 32 GB | `65.95.12.163:31027`<br>`ssh6.vast.ai:23380` | **$0.229/hr** 🌟 | Quebec, CA | 🟢 Live (Cheapest) |
| **Máy D** | `48333887` | 2x RTX 3090 | 48 GB | AMD EPYC 7R32 (96T) | 128 GB | 45 GB | `199.68.217.31:53040`<br>`ssh7.vast.ai:13886` | **$0.265/hr** | California, US | 💤 Standby (Leader 2) |
| **Máy G** | `48423230` | 2x RTX 3090 | 48 GB | Xeon E5-2686 v4 (72T) | 193 GB | 32 GB | `80.251.216.116:10048`<br>`ssh4.vast.ai:23230` | **$0.272/hr** | California, US | 🟡 Standby / Booting |
| **Máy H** | `48423711` | 2x RTX 3090 | 48 GB | AMD EPYC 7742 (128T) | 257 GB | 32 GB | `ssh8.vast.ai:23710` | **$0.278/hr** | Taiwan, TW | ⏳ Initializing |

---

## 🖥️ Chi Tiết Phần Cứng & Kết Nối Từng Node

### 1. Máy F (Node Siêu Rẻ - Đang Được Ưu Tiên Số 1)
* **Vast Instance ID**: `48423380` (Host ID: `53225`)
* **GPU**: 2x NVIDIA GeForce RTX 3090 (24GB x 2 = 48GB VRAM)
* **Driver / CUDA**: `595.71.05` / `CUDA 13.2`
* **CPU / Mainboard**: AMD Ryzen 5 5500 (6 Cores / 12 Threads) | ASUS ROG STRIX X570-E GAMING
* **RAM / Disk**: 64 GB DDR4 | 32 GB NVMe
* **Mạng & Vị trí**: Quebec, Canada (`65.95.12.163`)
* **Lệnh SSH Trực Tiếp**:
  ```bash
  ssh -p 31027 root@65.95.12.163 -L 8080:localhost:8080
  ```
* **Lệnh SSH Proxy**:
  ```bash
  ssh -p 23380 root@ssh6.vast.ai -L 8080:localhost:8080
  ```
* **Giá thuê**: **`$0.229 / giờ`** ($0.213 GPU + $0.016 Storage)
* **Dòng cấu hình trong `instances.txt`**:
  ```text
  ssh6.vast.ai 23380 48423380 0.230
  ```

---

### 2. Máy D (Node Dự Phòng Cao Cấp - EPYC 48 Core)
* **Vast Instance ID**: `48333887` (Host ID: `296571`)
* **GPU**: 2x NVIDIA GeForce RTX 3090 (48GB VRAM)
* **Driver / CUDA**: `580.95.05` / `CUDA 13.0`
* **CPU / Mainboard**: AMD EPYC 7R32 48-Core Processor (96 vCPUs)
* **RAM / Disk**: 128 GB RAM | 45 GB NVMe
* **Mạng & Vị trí**: California, US (`199.68.217.31`)
* **Lệnh SSH Trực Tiếp**:
  ```bash
  ssh -p 53040 root@199.68.217.31 -L 8080:localhost:8080
  ```
* **Lệnh SSH Proxy**:
  ```bash
  ssh -p 13886 root@ssh7.vast.ai -L 8080:localhost:8080
  ```
* **Giá thuê**: **`$0.265 / giờ`**
* **Dòng cấu hình trong `instances.txt`**:
  ```text
  ssh7.vast.ai 13886 48333887 0.265
  ```

---

### 3. Máy G (Node RAM Khủng - Xeon 193GB)
* **Vast Instance ID**: `48423230` (Host ID: `171047`)
* **GPU**: 2x NVIDIA GeForce RTX 3090 (48GB VRAM)
* **CPU**: Intel Xeon E5-2686 v4 (72 vCPUs)
* **RAM / Disk**: 193 GB RAM | 32 GB NVMe
* **Mạng & Vị trí**: California, US (`80.251.216.116`)
* **Lệnh SSH Trực Tiếp**:
  ```bash
  ssh -p 10048 root@80.251.216.116 -L 8080:localhost:8080
  ```
* **Lệnh SSH Proxy**:
  ```bash
  ssh -p 23230 root@ssh4.vast.ai -L 8080:localhost:8080
  ```
* **Giá thuê**: **`$0.272 / giờ`**
* **Dòng cấu hình trong `instances.txt`**:
  ```text
  ssh4.vast.ai 23230 48423230 0.272
  ```

---

### 4. Máy H (Node Hiệu Năng Cao - EPYC 7742 & PCIe Gen4)
* **Vast Instance ID**: `48423711` (Host ID: `116365`)
* **GPU**: 2x NVIDIA GeForce RTX 3090 (48GB VRAM - PCIe Gen 4.0 12.8 GB/s)
* **CPU**: AMD EPYC 7742 64-Core Processor (128 vCPUs) | Gigabyte MZ32-AR0-00
* **RAM / Disk**: 257 GB RAM | 32 GB Kioxia NVMe (3,254 MB/s)
* **Mạng & Vị trí**: Taiwan, TW (`61.71.33.195`)
* **Lệnh SSH Proxy**:
  ```bash
  ssh -p 23710 root@ssh8.vast.ai -L 8080:localhost:8080
  ```
* **Giá thuê**: **`$0.278 / giờ`**
* **Dòng cấu hình trong `instances.txt`**:
  ```text
  ssh8.vast.ai 23710 48423711 0.278
  ```

---

## 🛠️ Quy Trình Tự Động Định Tuyến & Tối Ưu Chi Phí
1. **Ưu tiên Chi phí**: Gateway luôn tự động sắp xếp và kết nối tới máy có giá rẻ nhất (**Máy F: $0.229/hr**).
2. **Failover Thông minh**: Nếu Máy F tắt hoặc bận, Gateway tự động chuyển sang **Máy D ($0.265/hr)** hoặc **Máy G ($0.272/hr)**.
3. **Auto-Stop an toàn**: Khi cụm chạy ổn định trên Leader, Gateway sẽ gửi lệnh `STOP` (không xóa) các máy dự phòng thừa để chỉ tốn tiền duy nhất 1 máy đang dùng.
