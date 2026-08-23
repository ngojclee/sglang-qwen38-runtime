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

Log: `/workspace/bootstrap_vllm.log` · Server: `:18020` (OpenAI-compatible, model `qwen3.8-27b`).

> ⚠️ PROFILE_3090_ULTRAFAST là reference từ playbook §8.3 (máy F), chưa re-verify
> qua bootstrap này trên máy mới. PROFILE_5060TI_LONG_KVARN_V1 verified trên
> e21220fe5193; fresh-machine reproduction CHƯA thực hiện (Phase B skipped).

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
