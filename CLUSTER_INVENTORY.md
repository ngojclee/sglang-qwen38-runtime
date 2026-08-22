# 🌐 Toàn Bộ Danh Sách Máy Chủ GPU Thuê Trên Vast.ai (Lịch Sử & Hiện Tại)

Tài liệu này ghi nhận đầy đủ danh bạ toàn bộ các máy chủ GPU mà hệ thống đã thuê từ trước đến nay (Máy A, B, C, D, E, F, G, H), phục vụ cụm suy luận **SGLang Qwen 3.8-27B DFlash2 Golden Runtime**.

---

## 📊 Bảng Tổng Hợp Chi Tiết Toàn Bộ Các Máy (A ➔ H)

| Tên Máy | Vast Instance ID | Model GPU & VRAM | CPU | RAM | NVMe Disk | Lệnh Kết Nối SSH Chuẩn | Giá Thuê ($/hr) | Vị Trí | Trạng Thái Vận Hành |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Máy A** | `48270104` | 2x RTX 3090 (48GB) | AMD EPYC | | 32 GB | | $0.260/hr | US | 🗑️ Đã hủy |
| **Máy B** | `48270992` | 2x RTX 3090 (48GB) | AMD EPYC | | 32 GB | | $0.265/hr | US | 🗑️ Đã hủy |
| **Máy C** | `48283311` | 2x RTX 3090 (48GB) | AMD EPYC | 128 GB | 32 GB | | $0.270/hr | US | 🗑️ Đã hủy |
| **Máy D** | `48333887` | 2x RTX 3090 (48GB) | AMD EPYC 7R32 (96T) | 128 GB | 45 GB | `ssh -p 53040 root@199.68.217.31`<br>`ssh -p 13886 root@ssh7.vast.ai` | **$0.265/hr** | California, US | 💤 Standby (Leader Backup) |
| **Máy E** | `48394592` | 2x RTX 3090 (48GB) | AMD EPYC 7502 (64T) | 128 GB | 32 GB | `ssh -p 34593 root@ssh3.vast.ai` | $0.269/hr | California, US | 🗑️ Đã hủy |
| **Máy F** | `48423230` | 2x RTX 3090 (48GB) | Intel Xeon E5-2686 v4 (72T) | 193 GB | 32 GB | `ssh -p 10134 root@80.251.216.116`<br>`ssh -p 23231 root@ssh4.vast.ai` | **$0.272/hr** | California, US | 🟢 Live (Đang nạp Model & Build) |
| **Máy G** | `48423380` | 2x RTX 3090 (48GB) | AMD Ryzen 5 5500 (12T) | 64 GB | 32 GB | `ssh -p 31027 root@65.95.12.163`<br>`ssh -p 23381 root@ssh6.vast.ai` | **$0.229/hr** 🌟 | Quebec, CA | 🟢 Live (Primary Leader - Rẻ nhất) |
| **Máy H** | `48423711` | 2x RTX 3090 (48GB - PCIe Gen4) | AMD EPYC 7742 (128T) | 257 GB | 32 GB | `ssh -p 55122 root@61.71.33.195`<br>`ssh -p 23711 root@ssh8.vast.ai` | **$0.278/hr** | Taiwan, TW | 🟢 Live (Đang nạp Model & Build) |

---

## 🔍 Thông Tin Kỹ Thuật Chi Tiết Từng Node Hiện Hữu

### 1. Máy G — Node Ưu Tiên Giá Rẻ Nhất (Primary Leader)
* **Vast Instance ID**: `48423380` (Host ID: `53225`)
* **GPU**: 2x NVIDIA GeForce RTX 3090 (48GB VRAM)
* **Driver / CUDA**: `595.71.05` / `CUDA 13.2`
* **CPU / Mainboard**: AMD Ryzen 5 5500 (6C / 12T) | ROG STRIX X570-E GAMING
* **RAM / Disk**: 64 GB RAM | 32 GB NVMe
* **Lệnh SSH Trực Tiếp**:
  ```bash
  ssh -p 31027 root@65.95.12.163 -L 8080:localhost:8080
  ```
* **Lệnh SSH Proxy**:
  ```bash
  ssh -p 23381 root@ssh6.vast.ai -L 8080:localhost:8080
  ```
* **Giá thuê**: **`$0.229 / giờ`**
* **Dòng Tunnel trong `instances.txt`**:
  ```text
  ssh6.vast.ai 23381 48423380 0.230
  ```

---

### 2. Máy D — Node Chuẩn Backup (AMD EPYC 48-Core)
* **Vast Instance ID**: `48333887` (Host ID: `296571`)
* **GPU**: 2x NVIDIA GeForce RTX 3090 (48GB VRAM)
* **Driver / CUDA**: `580.95.05` / `CUDA 13.0`
* **CPU / Mainboard**: AMD EPYC 7R32 48-Core Processor (96 vCPUs)
* **RAM / Disk**: 128 GB RAM | 45 GB NVMe
* **Lệnh SSH Trực Tiếp**:
  ```bash
  ssh -p 53040 root@199.68.217.31 -L 8080:localhost:8080
  ```
* **Lệnh SSH Proxy**:
  ```bash
  ssh -p 13886 root@ssh7.vast.ai -L 8080:localhost:8080
  ```
* **Giá thuê**: **`$0.265 / giờ`**
* **Dòng Tunnel trong `instances.txt`**:
  ```text
  ssh7.vast.ai 13886 48333887 0.265
  ```

---

### 3. Máy F — Node RAM Dung Lượng Lớn (193 GB RAM)
* **Vast Instance ID**: `48423230` (Host ID: `171047`)
* **GPU**: 2x NVIDIA GeForce RTX 3090 (48GB VRAM)
* **Driver / CUDA**: `595.84` / `CUDA 13.2`
* **CPU / Mainboard**: Intel Xeon E5-2686 v4 (72 vCPUs)
* **RAM / Disk**: 193 GB RAM | 32 GB NVMe
* **Lệnh SSH Trực Tiếp**:
  ```bash
  ssh -p 10134 root@80.251.216.116 -L 8080:localhost:8080
  ```
* **Lệnh SSH Proxy**:
  ```bash
  ssh -p 23231 root@ssh4.vast.ai -L 8080:localhost:8080
  ```
* **Giá thuê**: **`$0.272 / giờ`**
* **Dòng Tunnel trong `instances.txt`**:
  ```text
  ssh4.vast.ai 23231 48423230 0.272
  ```

---

### 4. Máy H — Node Băng Thông Cao & CPU 128 Thread (EPYC 7742)
* **Vast Instance ID**: `48423711` (Host ID: `116365`)
* **GPU**: 2x NVIDIA GeForce RTX 3090 (48GB VRAM - PCIe Gen4 12.8 GB/s)
* **Driver / CUDA**: `580.167.08` / `CUDA 13.0`
* **CPU / Mainboard**: AMD EPYC 7742 64-Core Processor (128 vCPUs) | Gigabyte MZ32-AR0-00
* **RAM / Disk**: 257 GB RAM | 32 GB Kioxia NVMe (3,254 MB/s)
* **Lệnh SSH Trực Tiếp**:
  ```bash
  ssh -p 55122 root@61.71.33.195 -L 8080:localhost:8080
  ```
* **Lệnh SSH Proxy**:
  ```bash
  ssh -p 23711 root@ssh8.vast.ai -L 8080:localhost:8080
  ```
* **Giá thuê**: **`$0.278 / giờ`**
* **Dòng Tunnel trong `instances.txt`**:
  ```text
  ssh8.vast.ai 23711 48423711 0.278
  ```

---

## 🎯 Cấu Hình File `/etc/vast/instances.txt` Chuẩn Thứ Tự Ưu Tiên Giá Rẻ:
```text
ssh6.vast.ai 23381 48423380 0.230
ssh7.vast.ai 13886 48333887 0.265
ssh4.vast.ai 23231 48423230 0.272
ssh8.vast.ai 23711 48423711 0.278
```
