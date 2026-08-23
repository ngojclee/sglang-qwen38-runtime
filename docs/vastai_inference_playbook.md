# 🚀 VAST.AI LLM DEPLOYMENT & INFERENCE PLAYBOOK
> **Chuẩn hóa vận hành cụm SGLang + DFlash2 cho Qwen3.8-27B-Uncensored — SSH Tunnel, Router CPA, Codex / Hermes / Oh My Pi Agent**
> Cập nhật: 23/08/2026 • Bản chuẩn duy nhất, mọi thay đổi cấu hình phải đồng bộ vào đây + GitHub `ngojclee/sglang-qwen38-runtime`.

---

## 📌 MỤC LỤC
1. [Tổng quan cụm & Kiến trúc](#1-tổng-quan-cụm--kiến-trúc)
2. [Cấu hình chuẩn Golden Runtime (Template)](#2-cấu-hình-chuẩn-golden-runtime-template)
3. [Vận hành: Tạo máy mới • Chuẩn hóa • Audit • Benchmark](#3-vận-hành)
4. [Hạ tầng kết nối: SSH Tunnel + Portainer Stack + CPA](#4-hạ-tầng-kết-nối)
5. [Cấu hình Client (Codex / Hermes)](#5-cấu-hình-client)
6. [Chuyên sâu kỹ thuật](#6-chuyên-sâu-kỹ-thuật)
7. [Bảng tra cứu sự cố (Troubleshooting)](#7-bảng-tra-cứu-sự-cố)
8. [Kết quả Benchmark cụm](#8-kết-quả-benchmark-cụm)

---

## 1. TỔNG QUAN CỤM & KIẾN TRÚC

### 🖥️ 1.1 Bản đồ cụm (tóm tắt)
> **Chi tiết phần cứng đầy đủ xem `CLUSTER_INVENTORY.md`** — file này chỉ giữ trạng thái vận hành.

| Máy | Vast ID | SSH Proxy (+1) | Direct | RAM | Vai trò | Trạng thái |
|---|---|---|---|---|---|---|
| **G** | 48423380 | ssh6.vast.ai:23381 | 65.95.12.163:31027 | 62GB | 🟢 **Leader** ($0.2296/h rẻ nhất) | LIVE — hicache 3.0, PASS 200K |
| **F** | 48423230 | ssh4.vast.ai:23231 | 80.251.216.116:10134 | 188GB | 🟢 Node phụ | LIVE — hicache 4.0 |
| **H** | 48423711 | ssh8.vast.ai:23711 | 61.71.33.195:55122 | 251GB | 🟢 Node phụ | LIVE — hicache 4.0 |
| **D** | 48333887 | ssh7.vast.ai:13887 | 199.68.217.31 | 125GB | ⛔ Chờ xóa | STOPPED (resources hết) |
| **I** | 48424397 | ssh3.vast.ai:24397 | 70.69.192.6 | 251GB | 🛡️ Failover ($2.13/tháng) | STOPPED (resources hết) |

> ⚠️ **Port SSH**: API Vast trả `ssh_port` (23230...) nhưng **port proxy đúng là +1** (23231...). Máy STOPPED không SSH vào được bằng mọi port — phải Start trước.

### 🌐 1.2 Kiến trúc kết nối
```text
Clients (Codex/Hermes/OMP) → CPA 10.21.1.101:8317 → vast-gateway:18000 → vast-tunnel:18001..18005 → SSH → node:18000
```
- **Proxmox 10.21.1.1** → CT 101 (alpine-docker): `vast-tunnel` (mở cổng động theo instances.txt), `vast-gateway` (router + auto-scaler), `cli-proxy-api` (CPA :8317).
- **vast-gateway** chọn leader theo giá rẻ nhất (`instances.txt` cost-sorted), tự sync từ Vast API bằng **direct IP** (proxy Vast hay "Connection closed").
- **SSH Key**: `C:/Users/ngocl/.ssh/id_ed25519` • **CT101 key**: `C:/Users/ngocl/.codex/secrets/ssh/10.21.1.1_ed25519` • **Vast API key**: `profiles/nyx/secrets/vast.env` (không hardcode).

---

## 2. CẤU HÌNH CHUẨN GOLDEN RUNTIME (TEMPLATE)

> **Nguyên tắc quan trọng:** Template Vast **KHÔNG chứa cờ SGLang trực tiếp** — chỉ có image + env + on-start. **Toàn bộ cờ do `bootstrap.sh` sinh ra** vào `/etc/sglang-args.conf` lúc máy boot. Muốn đổi chuẩn → sửa **1 nơi duy nhất** trên GitHub `ngojclee/sglang-qwen38-runtime` (main), mọi máy mới tạo tự lấy bản mới nhất.

### 📋 2.1 Thông số Template Vast (form Config)
| Trường | Giá trị |
|---|---|
| Template Name | `SGLang Qwen3.8 DFlash2 Ultra` |
| Image | `lmsysorg/sglang:v0.5.16` |
| Env / Docker Options | `SGLANG_ARGS="--host 127.0.0.1 --port 18000"` |
| On-start Script | `bash <(curl -sL https://raw.githubusercontent.com/ngojclee/sglang-qwen38-runtime/main/scripts/bootstrap.sh)` |
| Launch Mode | Jupyter + SSH + Direct |
| Disk | 32 GB |

> ⚠️ **Link onstart**: `ngojclee` (có chữ **j**) — dán thiếu thành `ngoclee` → 404, máy mới không boot được.

### 📋 2.1b Template vLLM (2×5060 Ti / 2×3090 — research long-context, 23/08/2026)
| Trường | Giá trị |
|---|---|
| Template Name | `VLLM Qwen3.8 DFlash2 Long-Context` |
| Image | `vastai/vllm:v0.27.1-cuda-13.0` |
| Env / Docker Options | *(để trống — bootstrap tự set)* |
| On-start Script | `bash <(curl -sL https://raw.githubusercontent.com/ngojclee/sglang-qwen38-runtime/main/vllm-profiles/bootstrap_vllm.sh)` |
| Launch Mode | Jupyter + SSH + Direct |
| Disk | **60 GB** |

> Bootstrap vLLM tự detect GPU (nvidia-smi): **2×3090 → PROFILE_3090_ULTRAFAST**
> (BF16/FLASH_ATTN, ref §8.3) · **2×5060 Ti → PROFILE_5060TI_LONG_KVARN_V1**
> (KVarN, frozen tag `qwen38-5060ti-long-v1`) · khác → STOP. Tự clone syv-ai repo,
> 13 patches, KVarN, tải model 19GB + drafter, launch :18020, verify. Log
> `/workspace/bootstrap_vllm.log`. ⚠️ 3090 branch chưa re-verify qua bootstrap mới.

### ⚙️ 2.2 Args chuẩn bootstrap sinh ra (2x3090, RAM ≥128GB)
```bash
--tensor-parallel-size 2 --speculative-algorithm DFLASH --speculative-draft-model-path /root/models/Qwen3.8-27B-DFlash2 --speculative-num-draft-tokens 8 --speculative-draft-model-quantization unquant --kv-cache-dtype fp8_e4m3 --quantization compressed-tensors --trust-remote-code --served-model-name Qwen3.8-27B-Uncensored --reasoning-parser qwen3 --tool-call-parser qwen3_coder --enable-strict-thinking --mem-fraction-static 0.90 --context-length 262144 --allow-auto-truncate --enable-cache-report --chunked-prefill-size 2048 --max-prefill-tokens 16384 --disable-custom-all-reduce --max-running-requests 4 --linear-attn-backend triton --enable-hierarchical-cache --hicache-ratio 4.0 --hicache-write-policy write_through --hicache-io-backend kernel --hicache-mem-layout page_first --host 127.0.0.1 --port 18000
```
- Profile tham chiếu: `sglang-profiles/qwen3.8-27b-awq-2x3090-dflash2.conf` (= GitHub `configs/sglang_2x3090_dflash2.conf`)

### 🧠 2.3 Bootstrap tự detect (không sửa tay) — dùng chung 1 template cho cả 2 loại GPU
| Thông số | **2× 5060 Ti 16GB** | **2× 3090 24GB** |
|---|---:|---:|
| `mem-fraction-static` | **0.90** | **0.90** |
| DFlash2 | ✅ | ✅ |
| Draft tokens | **6** | **8** |
| KV cache | FP8 E4M3 | FP8 E4M3 |
| Context | **262,144** | **262,144** |
| HiCache | **3.0** | **4.0** (theo RAM: ≥128GB→4.0, ≥96GB→3.5, ≥64GB→3.0, <64GB→2.0) |
| Linear attention | Triton | Triton |
| `chunked-prefill-size` | 2048 | 2048 |
| `max-prefill-tokens` | 16384 | 16384 |
| `max-running-requests` | **2** | **4** |
| Mục tiêu | ≥200K context + tốc độ tốt | ≥200K context + tốc độ cao |

- Models tự tải: target `hotdogs/Qwen3.8-27B-AWQ-INT4` + draft `z-lab/Qwen3.8-27B-DFlash2`; served name `Qwen3.8-27B-Uncensored`.
- Tự clone + patch SGLang (`fdebc93` + core patches), launch trên **port 18000**.
- Profile tham chiếu: `sglang-profiles/qwen3.8-27b-awq-2x3090-dflash2.conf` + `sglang-profiles/qwen3.8-27b-awq-2x5060ti-dflash2.conf` (= GitHub `configs/sglang_2x3090_dflash2.conf` + `configs/sglang_2x5060ti_dflash2.conf`).
- **1 template Vast duy nhất dùng cho cả 5060Ti lẫn 3090** — onstart trỏ tới bootstrap link chung, bootstrap tự detect GPU (≥22000MB VRAM → profile 3090; else → profile 5060Ti).

---

## 3. VẬN HÀNH

### 🚀 3.1 Tạo máy mới từ template
1. Vast.ai → **Templates** → chọn template chuẩn → **Save & Use**.
2. Chọn offer 2x3090 24GB (ưu tiên RAM ≥128GB, giá rẻ).
3. Máy boot → onstart chạy bootstrap: detect GPU/RAM → tải models → patch SGLang → launch :18000 (mất 8–15 phút).
4. Verify: `curl http://127.0.0.1:18000/health` = 200; `cat /etc/sglang-args.conf`.
5. Gateway auto-sync `instances.txt` (direct IP) → tunnel tự mở cổng → CPA dùng được ngay.

### 🔧 3.2 Chuẩn hóa máy đang chạy sai cấu hình
```bash
# 1. Clone repo + chạy bootstrap TỪ TRONG REPO (curl|bash KHÔNG áp được patch → crash)
git clone --depth 1 https://github.com/ngojclee/sglang-qwen38-runtime /root/sglang-qwen38-runtime
cd /root/sglang-qwen38-runtime && bash scripts/bootstrap.sh    # chạy nohup nền nếu SSH đóng

# 2. Nếu chỉ cần sửa args + restart (không rebuild):
cat > /root/start_sglang.sh << 'EOF'
#!/bin/bash
pkill -f sglang.launch_server 2>/dev/null; sleep 2
exec python3 -m sglang.launch_server --model-path /root/models/hotdogs-Qwen3.8-27B-AWQ-INT4 $(cat /etc/sglang-args.conf) >> /var/log/portal/sglang.log 2>&1
EOF
chmod +x /root/start_sglang.sh
sync; echo 3 > /proc/sys/vm/drop_caches   # giải phóng RAM buff/cache trước khi launch
setsid nohup /root/start_sglang.sh >/dev/null 2>&1 &
```
> ⚠️ **Pitfall đã trả giá:** (1) `curl | bash` không có thư mục `patches/` → source không vá → crash `HybridLinearKVPool` / `AttentionBackend.forward()`. (2) Máy RAM nhỏ (62GB) hicache 4.0 → OOM host memory — phải drop cache + dùng hicache 3.0. (3) Process launch phải `setsid` + `< /dev/null` nếu không bị SSH đóng giết.

### 🔍 3.3 Audit cụm
```bash
python scripts/audit_cluster.py     # Vast API + SSH health + xuất instances.txt cost-sorted
# Start/stop instance — DÙNG vastai CLI (API REST PUT bị 404):
"/c/Users/ngocl/AppData/Local/hermes/hermes-agent/venv/Scripts/vastai.exe" start instance 48424397
```

### ⚡ 3.4 Benchmark chuẩn (5 tầng 4K→262K)
```bash
python scripts/benchmark_token_5tier.py <SSH_HOST> <SSH_PORT>   # chạy nền + notify
```
Tiêu chuẩn đo: decode tok/s, TTFT, prefill tok/s, out_tokens (64), KV pool (`grep max_req_input_len /var/log/portal/sglang.log`), GPU temp/power, OOM/truncate trong log. Kết quả điền vào mục 8 + CLUSTER_INVENTORY.

### 💰 3.5 Quản lý chi phí
- **G** chạy leader ($0.2296/h) • **I** failover standby ($2.13/tháng) • **F/H** standby khi không dùng ($6.40/tháng).
- Auto-scaler vast-gateway tự tắt máy thừa/idle — khi làm việc set `AUTO_SCALE_ENABLED=false`.

---

## 4. HẠ TẦNG KẾT NỐI

### 🔌 4.1 Portainer Stack (CT 101) — Dynamic Tunnel + Gateway + CPA
> File chuẩn đầy đủ: `sglang-profiles/docker-compose.vast-gateway.portainer.yml` (= GitHub main `docker-compose.portainer.yml`) — copy vào Portainer → Stack → Edit → Update.

- **vast-tunnel**: đọc `instances.txt`, mở tunnel động `18001+i → 127.0.0.1:18000` (direct IP).
- **vast-gateway**: leader router + auto-scaler. Env quan trọng:
  - `AUTO_SCALE_ENABLED` (default `true`): `false` → **tạm ngưng auto start/stop** (chỉ sync instances.txt) — dùng khi benchmark/làm việc.
  - `IDLE_TIMEOUT_MINUTES` (30): tắt hết máy khi idle quá lâu.
  - `VAST_API_KEY` / `API_LLM_SERVER` / `VAST_PROVIDER_NAME`.
- **cli-proxy-api** (CPA :8317) — depends_on vast-gateway.

### ⚙️ 4.2 CPA `/home/Docker/CLIProxyAPI/config.yaml` (provider vastai)
```yaml
providers:
  - id: vastai
    name: "Vast AI SGLang"
    type: openai
    base_url: "http://vast-gateway:18000/v1"
    api_key: "<bearer key>"
    models:
      - id: "Qwen3.8-27B-Uncensored"
```

### 🔐 4.3 Quy tắc đổi model (tránh load nhầm/tràn đĩa)
```bash
pkill -f sglang || true
rm -rf /root/models/* /root/.cache/huggingface/hub/models--*
export HF_HUB_ENABLE_HF_TRANSFER=1
huggingface-cli download <model> --local-dir /root/models/<model> --local-dir-use-symlinks False
```

---

## 5. CẤU HÌNH CLIENT

### ⚙️ 5.1 Codex `~/.codex/config.toml`
```toml
model = "Qwen3.8-27B-Uncensored"
model_provider = "cliproxy"
model_reasoning_effort = "medium"
model_reasoning_summary = "auto"

[model_providers.cliproxy]
name = "cliproxy"
base_url = "http://10.21.1.101:8317/v1"
wire_specification = "openai"
requires_openai_auth = true
```

### ⚙️ 5.2 Codex `~/.codex/model_catalog.json`
```json
[{
  "slug": "Qwen3.8-27B-Uncensored",
  "display_name": "Qwen3.8 27B Uncensored (SGLang TP=2)",
  "context_window": 200000,
  "auto_compact_token_limit": 180000,
  "max_output_tokens": 32768,
  "default_output_tokens": 32768,
  "supports_reasoning_summaries": true,
  "default_reasoning_summary": "auto"
}]
```
> Reasoning levels SGLang chỉ nhận: `none | low | medium | xhigh` (không có `high` → HTTP 400).

---

## 6. CHUYÊN SÂU KỸ THUẬT

### 🎯 6.1 Tool Calling — `qwen3_coder` vs `qwen25`
- Qwen 2.5 sinh JSON `<tool_call>{...}</tool_call>` → parser `qwen25`.
- **Qwen 3 / Qwen-Coder sinh XML** `<function=...><parameter=...>` → **PHẢI dùng `--tool-call-parser qwen3_coder`**, nếu không model trả `tool_calls = []` (SGLang không hiểu XML = tool call).
- Kèm `--enable-strict-thinking`: ép model nhả text/tool call sau `</think>`, không để trống.

### 🛡️ 6.2 Chống lỗi Empty Content (`serving_chat.py`)
Khi model chỉ suy nghĩ trong `<think>` rồi ngắt EOS → Codex crash `model output must contain either output text or tool calls`. Patch trong `/sgl-workspace/sglang/python/sglang/srt/entrypoints/openai/serving_chat.py`:
```python
# Non-streaming (~1917):
if (not text or not text.strip()) and not tool_calls and reasoning_text:
    text = " "
# Streaming (~1644):
if not has_tool_calls.get(idx, False) and reasoning_tokens.get(idx, 0) > 0 and completion_tokens.get(idx, 0) == 0:
    yield build_sse_content(chunk_id=..., created=int(time.time()), model=request.model, index=idx, content=" ")
```

### ⚙️ 6.3 vLLM Backend (phương án thay thế)
```bash
python3 -m vllm.entrypoints.openai.api_server \
    --model /root/models/hotdogs-Qwen3.8-27B-AWQ-INT4 \
    --tensor-parallel-size 2 --gpu-memory-utilization 0.90 --max-model-len 131072 \
    --kv-cache-dtype fp8 --enable-chunked-prefill --enable-prefix-caching \
    --enable-reasoning --reasoning-parser deepseek_r1 --enable-auto-tool-choice \
    --tool-call-parser hermes --served-model-name Qwen3.8-27B-Uncensored \
    --api-key <key> --port 18000 --host 0.0.0.0
```

### 🧮 6.4 VRAM & chọn GPU (Qwen3.8-27B INT4)
| Nhu cầu | VRAM cần | GPU đề xuất | tok/s | Chi phí Vast |
|---|---|---|---|---|
| Agent code + 200K (chuẩn vàng) | ~40GB | **2× RTX 3090 24GB** | 22–29 (200K), 52–91 (≤100K) | $0.30–0.45/h |
| Tốc độ tối thượng | ~40GB | 2× RTX 4090 | >135 | $0.80–1.20/h |
| 262K BF16 gốc | ~52GB | 4× 5060 Ti 16GB | 75+ | $0.80–0.95/h |
| Context >500K | 65–80GB | 4× RTX 3090 | >105 | $0.75–1.10/h |

**Chi phí VRAM 262K + DFlash2**: INT4 ~34GB (dư 14GB trên 2×3090) • **FP8 ~40GB (lý tưởng, dư 8GB)** • BF16 ~52GB (thiếu 4GB → kịch trần 75K).

### 🚦 6.5 Memory Pressure & Tinh chỉnh 1 biến
- **Mức 1 🟢**: VRAM trống ~2GB → ổn định, giữ nguyên cấu hình.
- **Mức 2 🟡**: VRAM trống <500MB → "CUDA out of memory" / "KV cache allocation failed" → thiếu headroom.
- **Mức 3 🔴**: OOM ngay Prefill (Marlin GEMM) hoặc draft 8 OOM / draft 4 PASS → speculative đang ăn VRAM.

**Quy trình**: Giữ `mem-fraction` + draft hiện tại → test mốc cần đạt → nếu OOM **chỉ giảm 1 biến** (draft 8→6→4) → test lại → mới cân nhắc đổi mem-fraction. Không đổi 2 biến cùng lúc. (`supervisorctl restart` báo "ERROR (not running)" = lần trước đã crash OOM khi capture CUDA graph.)

---

## 7. BẢNG TRA CỨU SỰ CỐ

| Hiện tượng | Nguyên nhân gốc | Cách khắc phục |
|---|---|---|
| Model không gọi tool (`tool_calls = []`) | parser `qwen25` với model Qwen3 | Đổi `--tool-call-parser qwen3_coder` |
| `model output must contain either output text or tool calls` | Model ngắt sau `<think>` để rỗng | `--enable-strict-thinking` + patch serving_chat.py |
| HTTP 400 chọn reasoning `high` | SGLang thiếu alias `high` | Dùng `none/low/medium/xhigh` |
| Codex quay vòng 60s nén context | CPA timeout 60s mặc định | `timeout: 600s`, `stream_timeout: 1800s` trong CPA config |
| Mất kết nối giữa chừng `state deleted in TokenizerManager` | IP public drop socket | Đi qua SSH tunnel/gateway |
| SSH proxy `Connection closed` | Vast proxy quá tải | Dùng **direct IP** hoặc port +1 |
| Máy mới boot crash `HybridLinearKVPool` | Bootstrap `curl|bash` không áp patch | Clone repo + chạy bootstrap từ repo |
| SGLang không lên trên 18000 (chạy 30000) | args thiếu `--port 18000` | Bootstrap ≥806c9ae tự thêm; sửa args.conf + restart |
| `Not enough host memory available` | hicache-ratio quá cao với RAM nhỏ | Drop cache + giảm hicache (62GB → 3.0) |
| Start instance lỗi (API 404 / resources) | API REST không hỗ trợ; máy gốc hết | Dùng vastai CLI; resources hết = chờ/thuê lại |
| Máy vừa mở bị tắt ngay | vast-gateway auto-scaler | `AUTO_SCALE_ENABLED=false` khi làm việc |
| Hermes test SSH báo `#< CLIXML` | OpenSSH Windows gán pwsh.exe | Xóa registry `DefaultShell` trong `HKLM:\SOFTWARE\OpenSSH` |

---

## 8. KẾT QUẢ BENCHMARK CỤM

### 📊 8.1 Benchmark 23/08/2026 (config: mem 0.90 / draft 8 / fp8 / DFlash2, hicache theo máy)
| Máy | hicache | KV Pool | Tier | Decode tok/s | TTFT | Prefill tok/s | VRAM (2 GPU) | Nhiệt độ | RAM còn |
|---|---|---|---|---|---|---|---|---|---|
| **G** (62GB RAM) | 3.0 | **331,012** | 4K | **29.3** | 5.5s | 722 | 22.8GB | 66–69°C | 651MB |
| | | | 32K | **27.6** | 41.7s | 768 | | | |
| | | | 100K | **25.3** | 119.3s | 839 | | | |
| | | | **200K** | 🎉 **22.2 PASS** | 231.2s | 865 | | | |
| | | | 262K | ❌ | — | — | | | |
| **F** (188GB RAM) | 3.5 | 201,710 | 4K | **29.1** | 3.2s | 1267 | 23.8GB | 36–39°C | 142GB |
| | | | 32K | **27.8** | 24.2s | 1321 | | | |
| | | | 100K | **25.2** | 78.3s | 1277 | | | |
| | | | **200K** | ❌ OOM (prefill xong TTFT 90.6s, decode 0) | | | | | |
| | | | 262K | ❌ | — | — | | | |
| **H** (251GB RAM) | 4.0 | 201,616 | 4K | **19.7** | 6.2s | 645 | 23.9GB | 54–61°C | 101GB |
| | | | 32K | **18.6** | 35.2s | 910 | | | |
| | | | 100K | **17.4** | 108.8s | 919 | | | |
| | | | **200K** | ❌ OOM | 120.6s | 1658 | | | |
| | | | 262K | ❌ | — | — | | | |
| **D / I** | — | — | — | — | — | — | — | — | — |

> **Lý do OOM F/H tại 200K (đã điều tra log):** KV pool VRAM F/H = `201,710` tokens (cố định dù hicache 2.0/3.0/3.5/4.0 — **đã test đủ 4 mức, hicache chỉ đổi host RAM cache, KHÔNG đổi pool VRAM**). Request 200K + 64 output + Mamba state > 201,710 → `retract_decode` OOM → 0 output. G pool 331,012 (máy G phần cứng khác → pool lớn hơn) nên 200K PASS. **Muốn F/H pass 200K với draft 8: tăng `mem-fraction 0.90 → 0.92`** (máy D từng đạt 224,560 tokens @ 0.92) — **đã test: 0.92/draft 8 pool GIẢM còn 192,614 (không giúp); 0.92/draft 4 pool 224,829 (pass nhưng user chốt giữ draft 8)**.
> **Ghi chú:** G là máy leader — `max_total_num_tokens=331,012`; F/H `201,710` dù cùng mem 0.90/draft 8 (khác biệt phần cứng máy chủ: G ZOTAC VBIOS 94.02.42.80.9F + driver 595.71.05 — draft KV chỉ 0.16GB; F/H VBIOS 94.02.26.08.A8 + driver 595.84 — draft KV 0.48GB → F/H dành ~2.3GB VRAM nhiều hơn → pool nhỏ hơn).
> **Số liệu F (hicache 2.0, 23/08):** 4K 25.6 / 32K 27.7 / 100K 24.9 / 200K ❌ — pool 201,710.
> **Bản chất "PASS 200K" của máy D (bài cũ):** D pool 201,446 — bài đo cũ ghi "PASS (156K tok)" = chỉ nạp thực ~156K (Radix hit 71.6K trên prompt lặp) + output ngắn → không crash → tính PASS. Cùng tiêu chuẩn mới (nạp đủ 200K + 64 output) D cũng FAIL như F/H.
>
> ### 🏆 GIẢI PHÁP MAMBA (23/08, đã xác nhận) — pool 201K → 284K, PASS 200K với draft 8
> **Thêm 2 cờ: `--max-mamba-cache-size 4 --mamba-full-memory-ratio 0.5`** (giảm Mamba state cache — trước đó mặc định dự trữ ~7.7GB VRAM cho Mamba state, giờ chỉ dự trữ ~4GB) → **pool KV tăng 201,710 → 284,036 (F) / 283,949 (H)** — đủ 200K + 32K output (232K < 284K) mà **VẪN GIỮ draft 8 + mem 0.90 + DFlash2** (đúng "điểm ngọt" của user).
>
> | Máy | Pool trước | Pool sau (mamba giảm) | Benchmark (draft 8 / 0.90 / mamba giảm) |
> |---|---|---|---|
> | **F** | 201,710 | **284,036** | 4K **31.1** / 32K **29.1** / 100K **27.4** / **200K 23.5 ✅ PASS** (TTFT 171.9s, prefill 1163) / 262K ❌; VRAM 23.8GB; 37–41°C |
> | **H** | 201,622 | **283,949** | 4K **19.7** / 32K **19.1** / 100K **17.5** / **200K 15.8 ✅ PASS** (TTFT 226.3s, prefill 884) / 262K ❌; VRAM 23.9GB; 54–61°C |
>
> → **Đã push chuẩn mới vào bootstrap + 2 profile conf (commit `926f9bc` + `cc27b33`)** — máy mới mở tự áp. F/H giờ ngang G về mức context (trừ pool 284K vs 331K); không còn lý do kỹ thuật để bỏ máy vì 200K.
> ⚠️ **262K trên F/H — lý do fail là TRẦN CONTEXT, không phải pool:** prompt benchmark 262K sau tokenizer thành **335,421 tokens thật** → vượt context-length 262,144 → SGLang truncate (`max_req_input_len=262138`) → max_new_tokens bị cắt về 0 → decode 0. Pool 284K *đủ* 262K + output (262,208 < 284,036) — nhưng trần 262,144 + dự trữ 6 tokens không cho nạp đủ. **Tăng mamba sẽ GIẢM pool (mamba chiếm VRAM) → càng xa 262K** — không phải hướng đúng.
> **Mamba là gì / có ích gì:** Qwen3.8-27B là model hybrid — 16 layer attention cổ điển (cần KV cache) + **48 layer linear-attention kiểu Mamba** (dùng recurrent state, không cần KV). `--max-mamba-cache-size N` = giới hạn VRAM dự trữ cho state; `--mamba-full-memory-ratio` = phần state tối đa được cấp. Ích của Mamba: context dài "rẻ" hơn KV thuần (state nhỏ); state đầy đủ → accept rate DFlash tốt hơn → decode nhanh hơn. Tradeoff: state nhiều → tốn VRAM → pool KV nhỏ hơn.
>
> **📏 Ma trận mamba (F, draft 8 / mem 0.90):**
>
> | Config mamba | Pool KV | 200K | Ghi chú |
> |---|---|---|---|
> | size 4 / ratio 0.5 | 284,036 | 23.5 ✅ | bản đầu (đủ nhanh) |
> | **size 5 / ratio 0.9** 👑 | **280,457** | **24.2 ✅** | **CHỌN — pool 280K + nhanh hơn 6% (33.0 @4K / 31.3 @32K / 28.0 @100K)** |
> | size 6 / ratio 0.9 | 248,242 | ❌ | < 262K — bỏ |
> | size 8 / ratio 0.9 | 241,083 | ❌ | < 262K — bỏ |
> | draft 10 + size 4/0.5 | 276,878 | 21.5 ✅ | **chậm hơn draft 8 ~10%** — bỏ (draft model 10 tokens bị reject nhiều) |
>
> → **Draft 8 + size 5/0.9 là "điểm ngọt" cuối cùng** — pool 280K đủ 200K+32K output (232K < 280K), mamba state gần full (0.9) → vừa cân đối vừa nhanh nhất. Đã push bootstrap + 2 profile (commit `9455e90` + `adbb5f5`).
>
> ### 📊 8.1b TỔNG HỢP CHUẨN CUỐI (23/08) — flag tối ưu đã chọn & benchmark 2 dòng GPU
>
> **Kết luận tinh chỉnh (áp dụng mọi máy mới qua bootstrap GitHub):**
> - **draft 8 + mem 0.90 + DFlash2** = "điểm ngọt" (user chốt) — KHÔNG đổi
> - **`--max-mamba-cache-size 4 --mamba-full-memory-ratio 0.5`** = mamba cân đối → pool 201K→280K+ — **phát hiện chìa khóa 23/08** (chuẩn bootstrap; F tune size 5/0.9 nhanh +6% nhưng G OOM ở size 5 → bootstrap dùng size 4 an toàn mọi máy; size 6+ pool <262K — bỏ; draft 10 chậm hơn 10% — bỏ)
> - **hicache**: 3090 theo RAM host (≥128GB→4.0, ≥96→3.5, ≥64→3.0, <64→2.0); F/H thực tế pool KHÔNG đổi theo hicache 2.0/3.0/3.5/4.0 — hicache chỉ là host-RAM cache, không phải chìa khóa pool
> - **context-length 262144, KV FP8 E4M3, chunked-prefill 2048, max-prefill 16384, max-running-requests** theo GPU (3090=4, 5060Ti=2)
>
> | Dòng GPU | Máy | Pool KV | 4K | 32K | 100K | 200K | 262K | VRAM | Nhiệt | Giá/h |
> |---|---|---|---|---|---|---|---|---|---|---|
> | **2×3090 (24GB)** | **G** 👑 | **281,735** | 26.5 | 25.0 | 23.3 | **20.5 ✅** | ❌* | 22.8GB | 66–69°C | $0.2296 |
> | | **F** | **280,457** | **33.0** | **31.3** | **28.0** | **24.2 ✅** | ❌* | 23.8GB | 37–41°C | $0.2729 |
> | | ~~H~~ | ~~283,949~~ | — | — | — | — | — | — | — | ~~$0.2782~~ **destroyed 23/08** |
> | **2×5060Ti (16GB)** | A (vLLM) | ~75K | 35.0 | — | ❌ | ❌ | ❌ | — | — | — (cũ, đã xóa) |
> | | B (SGLang) | ~40.9K | 40.4 | ✅ 40.9K | ❌ | ❌ | ❌ | — | — | — (cũ) |
> | **4×5060Ti (16GB)** | C | 180.1K | 75.20 | ✅ | ✅ | ⚠️ HiCache | ⚠️ | — | — | — (cũ) |
>
> \* 262K fail trên G/F/H = **trần context 262,144 + prompt benchmark phình 335K tokens** (tokenizer), không phải pool — xem ghi chú mamba ở trên.
>
> **Tốc độ decode (tok/s) ghi nhận mới nhất, bài 5 tầng chuẩn:** F nhanh nhất dòng 3090 (31.1 @4K, 23.5 @200K) — ngang/trên G; H chậm nhất (~35% dưới F) dù CPU EPYC 7742 mạnh hơn — khác biệt máy chủ/GPU; GPU load H vẫn đạt 96% (không lỗi phần cứng).
>
> **Quyết định cụm (user):** giữ **G (leader) + F + I (failover standby $2.13/tháng)**, bỏ **H** (mắc hơn G $0.2782 vs $0.2296, chậm hơn F ~35%).
> **G "hy sinh":** RAM host chỉ 62GB (vs H 251GB) → hicache giới hạn 3.0 (không lên 4.0 được — RAM cạn 651MB khi chạy 200K); G config còn lại giống F/H (draft 8/0.90).
>
> ### 🔧 SỰ CỐ `!!!!!!!!` MÁY G (23/08) — đã xử lý
> G (image `vastai/sglang:v0.5.16`) chạy SGLang **patch thủ công KHÔNG đầy đủ** (chỉ mixed_qkv + pad_n Marlin tile, THIẾU GDN INT4 unpack + Triton fallback) → GDN weights không load đúng → model forward hỏng → **sinh `!!!!!!!!`**. F (bootstrap repo `ngojclee` + `sglang_working_tree.tar.gz` 35MB) chạy đúng.
> **Fix:** clone `ngojclee/sglang-qwen38-runtime` → chạy `scripts/bootstrap.sh` → apply `patches/apply_core_patches.py` + `sglang_working_tree.tar.gz` (vá đầy đủ) → reinstall editable. Kết quả: G hết `!!!!!!!!` (reasoning + code chuẩn), nhưng pool giảm 331K→281K (patch tar khác bản thủ công cũ) — **vẫn đủ 200K**.
> ⚠️ **Pitfall bootstrap:** khi bootstrap chạy lúc GPU đang bận (request production), `nvidia-smi` query VRAM có thể trả sai → detect nhầm profile 5060Ti (draft 6 / max-req 2) → phải sửa lại draft 8 / max-req 4 sau. Kiểm tra args.conf sau bootstrap.
> ⚠️ **G OOM ở mamba size 5/0.9** (draft KV allocation khác F) → G phải dùng size 4/0.5.

### 📜 8.2 Máy D & các thế hệ cũ (đo theo bài benchmark cũ `benchmark_unified.py` / `benchmark_token_200k.py` — tham chiếu)
> ⚠️ Bài đo cũ (Test 1 = tốc độ code solo tok/s) **khác format bài 5 tầng mới** — decode tok/s đo trên prompt ngắn, không phải decode tại từng mức context. Dùng để so sánh tương đối + chứng minh cấu hình.

| Máy (cấu hình) | KV VRAM | Tốc độ (Test 1) | 32K | 64K | 100K | 150K | 200K | 262K |
|---|---|---|---|---|---|---|---|---|
| **A** — 2×5060Ti vLLM | ~75K | 35.0 | ✅ | ⚠️ drop socket | ❌ | ❌ | ❌ | ❌ |
| **B** — 2×5060Ti SGLang DFlash2 | ~40.9K | 40.4 | ✅ (40.9K) | ❌ | ❌ | ❌ | ❌ | ❌ |
| **C** — 4×5060Ti DFlash2 | 180.1K | 75.20 | ✅ | ✅ | ✅ | ✅ (180K VRAM) | ⚠️ HiCache | ⚠️ HiCache |
| **D** — 2×3090 Baseline | 140,669 | 52.25 | ✅ 22.4s | ✅ 24.3s | ✅ 30.2s | ✅ 45.2s | ✅ HiCache | ✅ 140K+HiCache |
| **D** — 2×3090 FP8 **0.90/draft 8** 👑 | **201,446** | **62.05–91.53** | ✅ 23.7s | ✅ 26.1s | ✅ 32.6s | ✅ 48.4s | ✅ **56.8s** | ⚠️ 201.4K+33GB RAM |
| **D** — 2×3090 FP8 **0.92/draft 4** 🏆 | **224,560** | 56.18 | ✅ 24.4s | ✅ 78.3s | ✅ 55.2s | ✅ 49.9s | ✅ **56.3s** | ✅ **PASS 77.3s** |
| **D** — 2×3090 0.93/draft 2 | 232,537 | 44.03 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ PASS 77.5s |

- **Điểm mấu chốt:** máy D chứng minh 2×3090 **hoàn toàn đủ sức PASS 200K** (0.90/8: pool 201,446 — sát ngưỡng) và **PASS 262K khi nâng mem 0.92** (pool 224,560). F/H hôm nay pool 201,710 (sát D) — thiếu ~3K headroom nên 200K decode OOM; đúng hướng xử lý: **mem 0.90 → 0.92** cho F/H.
- Tool calling: D 0.90/8 = 1.52s, 0.92/4 = 1.72s, Baseline = 1.57s (mọi cấu hình PASS).
- Máy D cũ: 2× NVIDIA RTX 3090 24GB, AMD EPYC 7R32, 125.6GB RAM (đã xóa 23/08 — resources hết).

> Nhiệt độ full tải 68–69°C, công suất ~157–173W (50% TDP 350W). Prefill Radix hit tới **105,513 tok/s**.

---

*Tài liệu liên quan: `CLUSTER_INVENTORY.md` (phần cứng), `sglang-profiles/` (profile + compose), `BENCHMARK_AND_HARDWARE_COMPARISON.md` (máy D), GitHub `ngojclee/sglang-qwen38-runtime` (bootstrap/patch/scripts).*

---

### 🔬 8.3 BENCHMARK vLLM (23/08/2026, máy F 48423230) — FROZENLOCK INT4 + DFLASH2 W4A16

**TL;DR:** SGLang KHÔNG xử lý đúng AutoRound → output `!!!!!!!!` ("auto-round quantization is not fully optimized yet"). **vLLM 0.27.1 + DFlash2 backport (PR #52816) + FLASH_ATTN = WINNER: Code C1 244.2 tok/s, 200K LIVE PASS.**

| Profile | KV / Attention | Code C1 | Narrative C1 | 200K LIVE | Verdict |
|---|---|---|---|---|---|
| Superfast | FP8 / FlashInfer | 82.3 | 37.1 | chưa test (trần ~82) | ❌ FlashInfer+CUDA13 selector sort chậm (step ~55ms) |
| **Ultrafast** 👑 | **BF16 / FLASH_ATTN** | **244.2** | **109.8** | **✅ PASS (176K + needle đúng)** | ✅ **VƯỢT reference dual-ultrafast 231/128** |

**Cấu hình ULTRAFAST (winner):**
```bash
# vLLM 0.27.1 trong venv riêng + patches từ syv-ai/qwen38-27b-rtx3090:
#   dflash2-backport (PR #52816) + hybrid-kv-groups-v2-cudagraph + hybrid-sw-block-promote
#   + spec-decode-attn + sampler-small-topk-fast-softmax + vllm-pr50021-gdn-spec-bounds
#   + dflash2-lookup-drafting + marlin-int8-layer-select + marlin-int8-negative-scales
#   + spec-decode-int8-kv + speed-knobs-envs
env VLLM_SPEC_DECODE_ATTN=1 VLLM_USE_FLASHINFER_SAMPLER=0 \
    VLLM_DFLASH2_TORCH_TOPK=1 VLLM_DFLASH2_DRAFT_TOPK_TOPP=0 \
vllm serve Frozenlock/Qwen3.8-27B-int4-AutoRound \
  --quantization auto_round --max-model-len 200000 \
  --kv-cache-dtype bfloat16 --attention-backend FLASH_ATTN \
  --tensor-parallel-size 2 --gpu-memory-utilization 0.90 \
  --max-num-batched-tokens 16384 --max-num-seqs 8 \
  --mamba-ssm-cache-dtype float16 --reasoning-parser qwen3 \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder \
  --speculative-config '{"method":"dflash","model":"<drafter>","num_speculative_tokens":7}'
```
- Target: `Frozenlock/Qwen3.8-27B-int4-AutoRound` (18GB, AutoRound W4A16, MTP head quantized nhưng DÙNG DFlash2 không MTP)
- Drafter: `syvai/Qwen3.8-27B-DFlash2-W4A16` (1.19GB; **SPEC_N = 7** = block_size 8 − 1; KHÔNG tự đặt 8/15 nếu checkpoint không có)
- **Pitfall:** vLLM vanilla 0.27.1 có method `dflash` nhưng THIẾU `DFlash2DraftModel` → PHẢI apply dflash2-backport.patch (`Model architectures ['DFlash2DraftModel'] are not supported`).
- **Pitfall apply patch:** `pkill -f 'vllm.entrypoints'` tự giết ssh (chuỗi trùng) → dùng bracket `[v]llm.entrypoints`; worker giữ VRAM phải kill theo PID từ `nvidia-smi --query-compute-apps`.
- **Pitfall TP1:** Frozenlock nguyên bản KHÔNG fit 1×24GB (18GB model + 1.2GB drafter + graph ≈ 22GB → OOM dù gmu 0.72/len 8K). 2×3090 là tối thiểu; syv-ai requantize lm_head/embeddings để fit 1 card.
- **Pitfall CUDA-13:** FlashInfer radix top-k selector không JIT → fallback sort chậm (superfast 82 vs ultrafast 244). Trên CUDA-13, ưu tiên FLASH_ATTN + BF16 KV.
- **Topology F:** GPU0↔GPU1 = NV4 (4×NVLink) + P2P True → TP2 comm không bottleneck.
- Bootstrap template: `F:/_agentsync/docs/sglang-profiles/vast-bootstrap-vllm-ultrafast.sh`

---

### 🔬 8.4 BENCHMARK vLLM LONG-CONTEXT (23/08/2026, máy e21220fe5193 — 2× RTX 5060 Ti 16GB) — FROZENLOCK + DFLASH2 + KVarN

**TL;DR:** Trên 2×5060 Ti 16GB (160W/card), **KVarN là backend DUY NHẤT đạt 200K+** (pool 342,686). **LONG-CONTEXT / MEMORY WINNER — KHÔNG phải performance winner**: C1 @ 200K = **37.7 tok/s** (không đạt 109 tok/s reference — con số đó thuộc mode CTX=fast bf16 ~64K). FP8 max ~105K, BF16 ~70–140K → cả hai **FAIL 200K** trên 2×16GB.

| Hạng mục | Kết quả |
|---|---|
| Config | TP=2 · KVarN kvarn_k4v2_g128 · block 128 · PIECEWISE · GPU_UTIL 0.90 · max_len 262,144 · DFlash2 W4A16 SPEC_N=7 · PREFIX_CACHE=1 · **KV_MEM=3300000000** · **VLLM_V2_CUDAGRAPH_MEM_MIB=800** · max-num-batched-tokens **2048** (launcher default — plan ghi 16384 là nhầm từ config ultrafast §8.3; 2048 là giá trị đã verify) |
| KV pool | **342,686 tokens** |
| 200K LIVE | ✅ PASS — needle chính xác 100K/150K/200K, không truncate, 0 "!!!!!" |
| Ceiling | ✅ 220K (38.5) · 240K (38.7) · **261K (46.6) PASS** — trần = max_model_len 262,144 |
| C1 Code @ 200K | **37.7 tok/s** (5 runs 37.6–37.7) · TTFT cold 259.6s / cached 4.5s |
| Acceptance | ~73–79% avg · mean accepted 4.6–6.5 tok/step |
| Codex tool loop | ✅ 12 turns / 12 files · 0 malformed · 0 empty · 0 dropped |
| VRAM | 14,580/16,311 MiB/card (89.4%) |
| FP8 (CASE 2) | ❌ max thực tế ~104,720 (200K cần 3.48GiB KV, chỉ có 2.01GiB) |
| BF16 (Ultra) | ❌ không đủ 200K trên 2×16GB (~70–140K pool) |

**Kết luận:** 2×5060 Ti KHÔNG đạt "200K + >109 tok/s" — không tài liệu máy này thành config >=100 tok/s. So với reference KVarN của repo (1×3090 @112K = 32 tok/s), config này **nhỉnh hơn** (37.7 @ 200K, nhờ TP=2). 5060 Ti chỉ 160W + ~448GB/s bandwidth vs 3090 936GB/s.

- **Frozenlock format:** packing `auto_round:auto_gptq` → vLLM load qua AutoGPTQ Marlin; script quant của repo syv-ai (compressed-tensors) KHÔNG áp dụng được → lm_head/embed giữ bf16.
- **Memory tuning (chìa khóa boot 16GB):** KV_MEM repo default 5261334938 (tune 3090 24GB) → OOM boot trên 16GB; giảm KV_MEM=3300000000 + VLLM_V2_CUDAGRAPH_MEM_MIB=800 → pool 342K, boot sạch.
- **Pitfall:** `pkill -f "vllm serve"` tự giết SSH (chuỗi trùng) → dùng bracket; worker `VLLM::Worker_*`/`EngineCore` giữ VRAM sau khi kill wrapper → phải pkill cả 3 pattern.
- Snapshot: **tag `qwen38-5060ti-long-v1`** — profile `vllm-profiles/PROFILE_5060TI_LONG_KVARN_V1.conf`, bootstrap `vllm-profiles/bootstrap_vllm.sh`, results `docs/results/qwen38-5060ti.md` (repo GitHub `ngojclee/sglang-qwen38-runtime`).


