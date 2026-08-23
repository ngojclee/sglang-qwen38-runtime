# vLLM profiles (Qwen3.8-27B)

GPU-aware vLLM bootstrap for the Qwen3.8-27B long-context cluster (vLLM 0.27.1 +
syv-ai/qwen38-27b-rtx3090 patches + KVarN). This complements the SGLang cluster
in this repo (SGLang = throughput, vLLM = single-user long-context research).

## Profiles
| Profile | GPU | Context | C1 @200K | Status |
|---|---|---|---|---|
| `PROFILE_5060TI_LONG_KVARN_V1` | 2× RTX 5060 Ti 16GB | 262,144 (261K verified) | 37.7 tok/s | 🟢 FROZEN (tag qwen38-5060ti-long-v1) |
| `PROFILE_3090_ULTRAFAST` | 2× RTX 3090 24GB | — | — | ⏳ use syv-ai repo single-user CTX=fast directly |

## Use
```bash
# fresh 5060 Ti instance: clone + setup + launch + strict verify
git clone https://github.com/ngojclee/sglang-qwen38-runtime /workspace/runtime
cd /workspace/runtime && bash vllm-profiles/bootstrap_vllm.sh
# then: syv-ai repo setup (model download, patches, kvarn) — see profile conf
```

## Rules
- Never silently select another model/profile; unsupported GPU → STOP.
- Never silently fallback from DFlash2 or KVarN.
- Experimental configs → `PROFILE_5060TI_LONG_KVARN_EXPERIMENTAL`, never edit V1.
- 200K claim requires actual prompt tokens >= 200K (tokenizer-counted, not words).
- Every optimization needs an A/B result.
