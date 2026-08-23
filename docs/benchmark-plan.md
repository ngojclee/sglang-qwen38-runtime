# Benchmark Plan — Qwen3.8-27B / 2× RTX 5060 Ti 16GB (vLLM)

> Status log for the 3-phase program: **A SNAPSHOT → B REPRODUCTION → C EXPERIMENTS**.
> Phases are NOT mixed. Experimental configs never overwrite the frozen production profile.

## Phase A — FREEZE (DONE 2026-08-23)
- Profile: `vllm-profiles/PROFILE_5060TI_LONG_KVARN_V1.conf` (13-item snapshot)
- Bootstrap: `vllm-profiles/bootstrap_vllm.sh` (GPU-detect, strict select, pre/post checks)
- Results: `docs/results/qwen38-5060ti.md`
- Git tag: `qwen38-5060ti-long-v1`

## Phase B — FRESH MACHINE REPRODUCTION (SKIPPED 2026-08-23 — user decision, cost)
Fresh 2×5060 Ti instance → run ONLY PROFILE_5060TI_LONG_KVARN_V1 →
verify DFlash2/KVarN/pool/200K/needle → smoke test. **SKIPPED by user
(ngân sách). Reproducibility NOT yet verified on a fresh machine** — the
snapshot was verified only on source machine e21220fe5193. Bootstrap
`vllm-profiles/bootstrap_vllm.sh` is ready for when a fresh instance is rented.

## Phase C — PERFORMANCE RESEARCH (PARTIAL 2026-08-23: E1+E2 done, E3-E7 not run — cost)
Do NOT modify PROFILE_5060TI_LONG_KVARN_V1. Use PROFILE_5060TI_LONG_KVARN_EXPERIMENTAL.
Result table per experiment: CONFIG | C1 TOK/S | STEP TIME | ACCEPTED TOK/STEP |
ACCEPTANCE | KV CAPACITY | 200K PASS | VRAM | ERRORS

### E1 — STEP PROFILING (no restart, measured on production server)
| Context | C1 decode | Step time (8-token verify) |
|---|---|---|
| 2K | 119.0 tok/s | ~67 ms |
| 200K | 37.7 tok/s | ~212 ms |

**Bottleneck: KVarN attention at 200K adds ~145 ms/step (68% of step time).**
Drafter, GEMM, TP-comm are NOT the bottleneck. Note: at short context this
hardware does 119 tok/s — ABOVE the 109 reference; only the KVarN long-context
tax caps 200K at 37.7. (Repo reference: 1×3090 KVarN @112K = 32 tok/s.)

### E2 — INT8 ACTIVATION + MARLIN (VLLM_MARLIN_INPUT_DTYPE=int8, INT8_LAYERS=mlp)
| Config | Short ctx (2K) | 200K | 200K PASS | Verdict |
|---|---|---|---|---|
| Baseline W4A16 (V1) | 119.0 | **37.7** | ✅ | production |
| INT8/Marlin | 129.2 (+8.6%) | **31.5 (-16%)** | ✅ (200,097 tok no truncate) | ❌ REJECTED |

INT8 helps only when GEMM-bound (short ctx); at 200K the step is
KVarN-attention-bound, so the int8 quantize/dequantize overhead is pure loss.
Per decision rule: rejected — no gate_up/`.`/SPEC_N/scheduler experiments run.

### E3-E7 — NOT RUN (user decision, cost)

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
