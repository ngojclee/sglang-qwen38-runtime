# HiCache × KVarN Compatibility Research (2026-08-23)

**Goal (Phase 11D-G):** determine whether the SGLang hierarchical KV cache
(HiCache) can be used together with the KVarN KV backend in the frozen
vLLM stack — WITHOUT forcing an unsafe integration.

## Questions & evidence

### 1. Is HiCache available in this exact vLLM 0.27.1 stack?
**NO.** Verified on the production machine (vLLM 0.27.1 at
`/usr/local/lib/python3.12/dist-packages/vllm`):
```
grep -rin "hicache" <vllm tree>            → 0 hits
grep -rn "enable_hierarchical_cache" <tree> → 0 hits (no such CLI arg)
grep -rn "hicache" kvarn/                  → 0 hits
```
No `--enable-hierarchical-cache`, no `hicache-*` flags, no host-RAM KV
hierarchy code anywhere in the tree.

### 2. Is HiCache available only in SGLang?
**YES.** `--enable-hierarchical-cache` + `--hicache-ratio/write-policy/io-backend/
mem-layout` are SGLang runtime flags (in use on the SGLang cluster G/F via
the 26-flag profile). They are not part of vLLM 0.27.1 (upstream or this
patched tree).

### 3. Can KVarN compressed KV be stored/evicted/restored through a hierarchical cache?
**N/A — no hierarchical cache exists in this runtime to store/evict/restore through.**
KVarN KV (kvarn_k4v2_g128, 128-token tiles, 4-bit keys / 2-bit values with
Hadamard rotation + variance normalization) lives in vLLM's KV pool. The
only vLLM 0.27.1 reuse mechanism is **prefix caching** (already enabled in V1:
`--enable-prefix-caching --mamba-cache-mode align --prefix-match-unit 128`),
which keeps KV resident on GPU — it is not host-RAM offload.

### 4. Does HiCache expect a standard KV format incompatible with KVarN?
Conceptually yes — SGLang's HiCache pages its own KV pool (fp8/bf16 blocks in
SGLang layout); KVarN is a vLLM-native attention backend with a compressed
tile format and its own page alignment. There is no shared format and no
SGLang-side KVarN support either.

### 5. Does enabling HiCache change the KVarN attention path?
**N/A.** There is nothing to enable in this stack. Enabling it would require
porting SGLang's HiCache subsystem into vLLM 0.27.1 AND teaching it KVarN's
quantized tile format — a major, unverified, unsafe integration.

### 6. Is there an existing integration or patch?
**NO.** None of the 13 applied patches touch hierarchical caching
(see optimization-audit-qwen38.md); the kvarn/ port has no hicache code;
no upstream vLLM 0.27.1 HiCache exists.

## Verdict
```
KVarN + HiCache = INCOMPATIBLE in this stack.
HiCache is SGLang-only; vLLM 0.27.1 has no hierarchical KV cache;
KVarN has no SGLang-side equivalent.
→ STOP. Do not force an unsafe integration. (Phase 11D-G rule)
→ Phase H (1-4 concurrent × 200K HiCache tests) NOT executed.
```

## What V1 already has for long-context capacity (no HiCache needed)
- KVarN pool: **342,686 tokens** (max_model_len 262,144) — 1 full 261K session
  resident with room; 200K sessions can be multiplexed within the pool.
- Prefix caching: turn-2+ over the same document ≈ 4.5 s TTFT (vs 259 s cold).
- Verified: 200K/220K/240K/261K needle PASS; tool loop 12/12 clean.

## Future option (outside this stack)
If host-RAM KV offload is ever wanted with vLLM + KVarN, it requires an
upstream vLLM feature (not present in 0.27.1) or a dedicated port — out of
scope for PROFILE_5060TI_LONG_KVARN_V1 and not recommended without a
prototype + A/B.
