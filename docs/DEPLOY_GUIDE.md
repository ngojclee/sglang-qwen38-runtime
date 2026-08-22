# 🚀 SGLang Qwen3.8 Deployment Guide (NVIDIA RTX 3090 / 4090)

## 📌 Tổng Quan Kiến Trúc
Kho lưu trữ này cung cấp **2 phương thức triển khai chuẩn hóa** từ cùng một nguồn mã nguồn duy nhất:

```text
                                GitHub (Source of Truth)
                                           │
                                ┌──────────┴──────────┐
                                │                     │
                        GitHub Actions            Bootstrap
                                │                     │
                                ▼                     ▼
                              GHCR             git clone & patch
                     sglang-qwen38-runtime        (3 giây vá)
                                │                     │
                                └──────────┬──────────┘
                                           ▼
                                🚀 Qwen3.8-27B Live
```

---

## 🥇 PHƯƠNG THỨC 1: DOCKER / GHCR (Golden Image - Khuyên dùng)

### 1. Kéo Docker Image từ GHCR
```bash
docker pull ghcr.io/ngojclee/sglang-qwen38-runtime:v0.1.0
```

### 2. Chạy Container (Gắn Volume Model ngoài)
```bash
docker run --gpus all --ipc=host --net=host \
  -v /root/models:/root/models \
  ghcr.io/ngojclee/sglang-qwen38-runtime:v0.1.0 \
  --config /etc/sglang/configs/sglang_dflash2_fast.conf
```

---

## 🥈 PHƯƠNG THỨC 2: BOOTSTRAP SCRIPT (Nhẹ & Cực Nhanh)
Dùng khi thuê máy Vast.ai / RunPod đã có sẵn image SGLang (`lmsysorg/sglang:v0.5.16`).

### 1. Clone repo và chạy bootstrap:
```bash
git clone https://github.com/ngojclee/sglang-qwen38-runtime.git /opt/sglang-qwen38-runtime
cd /opt/sglang-qwen38-runtime
bash scripts/bootstrap.sh
```

### 2. Khởi động theo Profile mong muốn:
- **Tốc độ siêu nhanh DFlash2 (~91.5 tok/s)**:
  ```bash
  bash scripts/start_dflash2.sh
  ```
- **Context siêu dài (>262K - 1 Triệu Tokens)**:
  ```bash
  bash scripts/start_262k.sh
  ```

### 3. Kiểm tra tự động:
```bash
bash scripts/verify.sh
```

---

## 📦 Tải Trọng Số Model (Nếu chưa có trên ổ đĩa)
```bash
export HF_HUB_ENABLE_HF_TRANSFER=1

# 1. Tải Base Model INT4 AWQ
huggingface-cli download hotdogs/Qwen3.8-27B-abliterated-AWQ-INT4 \
  --local-dir /root/models/hotdogs-Qwen3.8-27B-AWQ-INT4 \
  --local-dir-use-symlinks False

# 2. Tải Draft Model DFlash2
huggingface-cli download z-lab/Qwen3.8-27B-DFlash2 \
  --local-dir /root/models/Qwen3.8-27B-DFlash2 \
  --local-dir-use-symlinks False
```
