# Optimization Audit — Qwen3.8-27B vLLM stack (2026-08-23)

Classification of every flag in the old SGLang "26-flag" Golden Runtime
(`configs/sglang_production_26_flags.conf`) against the **vLLM 0.27.1 +
KVarN + DFlash2 W4A16** production stack (PROFILE_5060TI_LONG_KVARN_V1).

## Legend
- **A** = already implemented by the current vLLM/patch/runtime (in use or available)
- **B** = already tested and rejected
- **C** = incompatible with the current KVarN/DFlash2 path — do NOT enable
- **D** = untested and potentially useful
- **E** = SGLang-only / not applicable to vLLM

## Classification
| # | Old flag (SGLang) | Class | vLLM equivalent / note |
|---|---|---|---|
| 1 | `--model-path hotdogs-...AWQ-INT4` | E | SGLang artifact; vLLM V1 = Frozenlock/Qwen3.8-27B-int4-AutoRound (`--model`) |
| 2 | `--quantization compressed-tensors` | C | would force wrong loader; Frozenlock = auto-round/auto_gptq (AutoGPTQ Marlin), drafter CT auto-detected |
| 3 | `--tensor-parallel-size 2` | A | `--tensor-parallel-size 2` — in use |
| 4 | `--trust-remote-code` | C | not needed; qwen3_5 native in 0.27.1 |
| 5 | `--served-model-name` | A | `--served-model-name qwen3.8-27b` — in use |
| 6 | `--reasoning-parser qwen3` | A | in use |
| 7 | `--tool-call-parser qwen3_coder` | A | in use |
| 8 | `--enable-strict-thinking` | C | SGLang mechanism; V2 runner rejects thinking_token_budget; Qwen template handles thinking |
| 9 | `--mem-fraction-static 0.90` | A | `--gpu-memory-utilization 0.90` + KV_MEM pin — in use |
| 10 | `--context-length 262144` | A | `--max-model-len 262144` — in use |
| 11 | `--allow-auto-truncate` | C | vLLM rejects >max_model_len (400). Keep the 400 — 200K claims must use REAL tokens |
| 12 | `--enable-cache-report` | E | SGLang-only reporting |
| 13 | `--chunked-prefill-size 2048` | A | `--max-num-batched-tokens 2048` — VERIFIED production value, do not change |
| 14 | `--max-prefill-tokens 16384` | B | direction tested+rejected: repo gotcha #7 — larger prefill chunks inflate activation peak, shrink pool, worse; 2048 verified |
| 15 | `--disable-custom-all-reduce` | A | vLLM flag exists; also already the effective state (no P2P on this box) |
| 16 | `--max-running-requests 4` | A | `--max-num-seqs`; production = 2 (CTX=huge repo value) |
| 17 | `--host 127.0.0.1 --port 18000` | A | vLLM `--host/--port`; production 0.0.0.0:18020 |
| 18 | `--linear-attn-backend triton` | E | SGLang kernel knob; vLLM uses own GDN kernels + `--mamba-ssm-cache-dtype float16` |
| 19 | `--enable-hierarchical-cache` | E | **SGLang-only — NOT in vLLM 0.27.1** (verified: zero "hicache" hits in vllm tree) → see hicache-kvarn-research.md |
| 20 | `--hicache-ratio 2.0` | E | SGLang-only |
| 21 | `--hicache-write-policy write_through` | E | SGLang-only |
| 22 | `--hicache-io-backend kernel` | E | SGLang-only |
| 23 | `--hicache-mem-layout page_first` | E | SGLang-only |
| 24 | `--speculative-algorithm DFLASH` | A | `SPEC=dflash2` — in use |
| 25 | `--speculative-draft-model-path` | A | `--speculative-config {"method":"dflash","model":...}` — in use |
| 26 | `--speculative-num-draft-tokens 8` | A/B | concept A (`num_speculative_tokens`); production = **7** (DFlash2 checkpoint-native block; repo: do not force 8/15) |
| 27 | `--speculative-draft-model-quantization unquant` | C | SGLang knob; vLLM uses the W4A16 drafter's own compressed-tensors config |

## Summary
- **A (carry forward):** 10 — already in V1.
- **B (rejected):** 1 — max-prefill-tokens direction (2048 verified).
- **C (incompatible):** 5 — quantization override, trust-remote-code, strict-thinking,
  auto-truncate, draft-quantization.
- **D (untested):** 0 carried — remaining candidate experiments (SPEC_N 9/11,
  scheduler 16K/32K, int4_per_token_head, turboquant) belong to Phase C E3-E7, not
  this flag list.
- **E (SGLang-only):** 9 — HiCache group (5), cache-report, linear-attn-backend,
  model-path artifact, (strict-thinking already C/E).

**No old flag is added to V1.** The 26-flag list must NOT be copied into the
vLLM profile. Production flags come from the repo launcher + V1 conf only.
