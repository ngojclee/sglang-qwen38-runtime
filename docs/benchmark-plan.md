# Benchmark Plan — Qwen3.8-27B / 2× RTX 5060 Ti 16GB (vLLM)

> Status log for the 3-phase program: **A SNAPSHOT → B REPRODUCTION → C EXPERIMENTS**.
> Phases are NOT mixed. Experimental configs never overwrite the frozen production profile.

## Phase A — FREEZE (DONE 2026-08-23)
- Profile: `vllm-profiles/PROFILE_5060TI_LONG_KVARN_V1.conf` (13-item snapshot)
- Bootstrap: `vllm-profiles/bootstrap_vllm.sh` (GPU-detect, strict select, pre/post checks)
- Results: `docs/results/qwen38-5060ti.md`
- Git tag: `qwen38-5060ti-long-v1`

## Phase B — FRESH MACHINE REPRODUCTION (PENDING)
Fresh 2×5060 Ti instance → run ONLY PROFILE_5060TI_LONG_KVARN_V1 →
verify DFlash2/KVarN/pool/200K/needle → smoke test. Reproducible only if
fresh deployment reaches the expected backend/config.

## Phase C — PERFORMANCE RESEARCH (PENDING)
Do NOT modify PROFILE_5060TI_LONG_KVARN_V1. Use PROFILE_5060TI_LONG_KVARN_EXPERIMENTAL.
Result table per experiment: CONFIG | C1 TOK/S | STEP TIME | ACCEPTED TOK/STEP |
ACCEPTANCE | KV CAPACITY | 200K PASS | VRAM | ERRORS

1. **Step profiling** — locate the dominant component of the ~37.7 tok/s step
   (draft / verify attention / KVarN attention / GEMM / sampler / mamba state /
   CUDA graph / TP comm / sync).
2. **INT8 activation + Marlin** — INT8_LAYERS=mlp → gate_up → `.` (one at a time).
3. **Draft tokens** — SPEC_N=7 → 9 → 11 (only if supported).
4. **Scheduler** — max-num-batched-tokens 2048 (VERIFIED production) → 16384 → 32768.
5. **int4_per_token_head** — investigate vs KVarN overhead, retain >=200K.
6. **TurboQuant** — only if 1-5 don't help.
7. **Concurrency** — 1-4 concurrent after best single-request config.

## Decision rule (replace production ONLY if)
200K actual context + correct needle + DFlash2 ACTIVE + no "!!!!!" + no malformed
tool calls + no OOM. Faster-but-loses-200K does NOT replace production.

## Final merge rule
Never auto-overwrite. If an experimental profile is clearly superior → update
profile/docs/bootstrap + new tag `qwen38-5060ti-long-v2`. Otherwise keep V1.
