# ⚡ SGLang Qwen3.8 Optimized Runtime (2× RTX 3090 / 4090)

> **Golden runtime package for Qwen3.8-27B INT4 AWQ with native Hybrid GDN Triton dequantization, DFlash2 speculative decoding (~91.5 tok/s), and HiCache PCIe RAM offload (>262K context).**

---

## 🌟 Tính Năng Nổi Bật
- 🚀 **Tốc độ 91.53 tokens/giây**: Tăng tốc 1.74x với `Qwen3.8-27B-DFlash2` (Block size 8).
- 🧠 **Hỗ trợ 262K - 1M Context**: Tối ưu hóa 48 tầng GDN $O(1)$ và bộ nhớ đệm phân tầng HiCache RAM.
- 🛠️ **Tool Calling Chuẩn Xác**: Tích hợp parser `qwen3_coder` streaming XML chuyên dụng cho Codex / Roo-Code / OpenCode.
- 📦 **Dual Deployment Ready**: Hỗ trợ cả **Docker GHCR Golden Image** (`v0.1.0`, `stable`) và **1-Click Bootstrap Script** (3 giây).
- 🏷️ **Clean Model Catalog**: Đã cố định tên model API duy nhất: `Qwen3.8-27B-Uncensored`.

---

## 📁 Cấu Trúc Kho Lưu Trữ

```text
sglang-qwen38-runtime/
├── .github/
│   └── workflows/
│       └── docker-publish.yml          # GitHub Actions build GHCR Golden Image
├── docker/
│   ├── Dockerfile                      # SGLang v0.5.16 + GDN/DFlash2 patch
│   └── entrypoint.sh                   # Script khởi chạy container
├── patches/
│   └── sglang_qwen38_working.patch     # Unified diff 7 file SGLang
├── configs/
│   ├── sglang_dflash2_fast.conf        # Profile 1: DFlash2 ~91.5 tok/s (< 64k)
│   ├── sglang_262k_max_context.conf    # Profile 2: Max context 262k (~52.6 tok/s)
│   └── sglang_production_26_flags.conf # Toàn bộ 26 cờ sản xuất
├── scripts/
│   ├── bootstrap.sh                    # 1-click bootstrap và patch kiểm tra version
│   ├── start_dflash2.sh                # Khởi động bản DFlash2
│   ├── start_262k.sh                   # Khởi động bản Max Context
│   └── verify.sh                       # Kiểm tra sức khỏe và benchmark tự động
└── docs/
    ├── DEPLOY_GUIDE.md                 # Hướng dẫn chi tiết triển khai
    └── BENCHMARK_COMPARISON.md         # Bảng benchmark đo kiểm thực tế
```

---

## 🚀 Triển Khai Nhanh

Xem hướng dẫn chi tiết tại [docs/DEPLOY_GUIDE.md](docs/DEPLOY_GUIDE.md).

### Cách 1: Chạy bằng Docker Image (GHCR)
```bash
docker run --gpus all --ipc=host --net=host \
  -v /root/models:/root/models \
  ghcr.io/ngojclee/sglang-qwen38-runtime:v0.1.0
```

### Cách 2: Chạy bằng Bootstrap Script (Máy đã có SGLang)
```bash
git clone https://github.com/ngojclee/sglang-qwen38-runtime.git /opt/sglang-qwen38-runtime
cd /opt/sglang-qwen38-runtime
bash scripts/bootstrap.sh
bash scripts/start_dflash2.sh
```
