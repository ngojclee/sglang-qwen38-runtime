# vLLM profiles (Qwen3.8-27B)

GPU-aware vLLM bootstrap for the Qwen3.8-27B long-context cluster (vLLM 0.27.1 +
syv-ai/qwen38-27b-rtx3090 patches + KVarN). This complements the SGLang cluster
in this repo (SGLang = throughput, vLLM = single-user long-context research).

## Profiles
| Profile | GPU | Context | C1 @200K | Status |
|---|---|---|---|---|
| `PROFILE_5060TI_LONG_KVARN_V1` | 2× RTX 5060 Ti 16GB | 262,144 (261K verified) | 37.7 tok/s | 🟢 FROZEN (tag qwen38-5060ti-long-v1) |
| `PROFILE_3090_ULTRAFAST` | 2× RTX 3090 24GB | — | — | ⏳ use syv-ai repo single-user CTX=fast directly |

## Use — Vast template (create a NEW machine from scratch)

**On-start link (duy nhất, tự nhận diện GPU):**
```bash
bash <(curl -sL https://raw.githubusercontent.com/ngojclee/sglang-qwen38-runtime/main/vllm-profiles/bootstrap_vllm.sh)
```

**Vast template config (Config form):**
| Trường | Giá trị |
|---|---|
| Template Name | `VLLM Qwen3.8 DFlash2 Long-Context` |
| Image | `vastai/vllm:v0.27.1-cuda-13.0` |
| Env / Docker Options | *(để trống — bootstrap tự set)* |
| On-start Script | link ở trên |
| Launch Mode | Jupyter + SSH + Direct |
| Disk | **60 GB** (model 19GB + runtime ~25GB) |

Bootstrap tự làm: detect GPU (nvidia-smi) → chọn profile → clone syv-ai repo →
apply 13 patches → KVarN → tải Frozenlock + DFlash2 W4A16 → launch → verify
(DFlash2DraftModel, SPEC_N=7, KVARN, pool, health). Không support GPU → STOP.

- `2× RTX 3090 (≥24GB)` → **PROFILE_3090_ULTRAFAST** (BF16/FLASH_ATTN, ref playbook §8.3)
- `2× RTX 5060 Ti (≥16GB)` → **PROFILE_5060TI_LONG_KVARN_V1** (KVarN)
- khác → STOP, không silent fallback

Log: `/workspace/bootstrap_vllm.log` · Server: `:18000` (OpenAI-compatible, model `Qwen3.8-27B-Uncensored` — khớp CPA provider `ln.vastai` + Codex model_catalog, override qua `EXTRA_ARGS`).

> ⚠️ PROFILE_3090_ULTRAFAST là reference từ playbook §8.3 (máy F), chưa re-verify
> qua bootstrap này trên máy mới. PROFILE_5060TI_LONG_KVARN_V1 verified trên
> e21220fe5193; fresh-machine reproduction CHƯA thực hiện (Phase B skipped).

## Vast-tunnel / CPA integration (2026-08-23)
- **Deployment port = 18000** (tunnel `vast-tunnel` luôn forward tới `node:18000`).
  Profile V1 frozen ghi PORT=18020 — deployment dùng 18000, chỉ khác port, không
  đụng performance config. Khi chạy qua supervisor (máy đang bật), server tự lên
  lại sau stop/start/reboot (supervisor service `vllm` → `/workspace/start_supervised.sh`).
- Gateway leader: vast-gateway chọn leader theo **giá rẻ nhất** — máy vLLM 5060 Ti
  ($0.1887/h) rẻ hơn G ($0.2296) → nếu nằm trong instances.txt auto-sync, nó sẽ
  thành leader và đá G. **Quyết định routing là của user** (xem playbook §8.4).
- CPA: chỉ cần provider trỏ `http://vast-gateway:18000/v1` (leader) HOẶC provider
  riêng trỏ thẳng `http://vast-tunnel:180XX/v1` (máy vLLM — port phụ thuộc thứ tự
  instances.txt, hiện tại rẻ nhất → 18001).
- **Tunnel-ready**: bootstrap tự append pubkey `vast-tunnel` vào
  `/root/.ssh/authorized_keys` (idempotent, PHASE 2b) → máy mới không cần thêm key
  tay, vast-tunnel CT101 SSH vào được ngay (cần private key CT101 khớp — xem playbook).

## Manual (nếu không dùng template)
```bash
git clone https://github.com/ngojclee/sglang-qwen38-runtime /workspace/runtime
cd /workspace/runtime && bash vllm-profiles/bootstrap_vllm.sh
```

## Rules
- Never silently select another model/profile; unsupported GPU → STOP.
- Never silently fallback from DFlash2 or KVarN.
- Experimental configs → `PROFILE_5060TI_LONG_KVARN_EXPERIMENTAL`, never edit V1.
- 200K claim requires actual prompt tokens >= 200K (tokenizer-counted, not words).
- Every optimization needs an A/B result.
- **Reproducibility NOT yet verified on a fresh instance** (Phase B skipped by
  user, cost). This profile + bootstrap are the snapshot, not a proof.
