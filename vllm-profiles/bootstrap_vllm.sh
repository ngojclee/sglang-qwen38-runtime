#!/bin/bash
# ============================================================================
# bootstrap_vllm.sh — GPU-aware bootstrap for Qwen3.8-27B vLLM serving
# PHASE A3+A4: hardware detect -> strict profile select -> pre/post launch checks
#
# Profiles:
#   2x RTX 3090 (>=24GB)  -> PROFILE_3090_ULTRAFAST   (syv-ai repo single-user
#                            CTX=fast reference; see vllm-profiles/README.md)
#   2x RTX 5060 Ti (>=16GB)-> PROFILE_5060TI_LONG_KVARN_V1
#   anything else          -> STOP (no silent selection)
#
# Usage: bash bootstrap_vllm.sh            (clone+setup+launch on fresh instance)
#        bash bootstrap_vllm.sh --launch   (skip setup, launch only)
# ============================================================================
set -u
WORK=/workspace
REPO=$WORK/qwen-serving
PROFILE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG=$WORK/bootstrap_vllm.log
exec > "$LOG" 2>&1

say() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { say "STOP: $*"; exit 1; }

# ---------------------------------------------------------------
# PHASE A3 — hardware detection
# ---------------------------------------------------------------
say "=== GPU detection ==="
GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits 2>/dev/null | head -1)
GPU_NAMES=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | sort -u | tr '\n' '|')
GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
GPU_CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)
GPU_PCIE_GEN=$(nvidia-smi --query-gpu=pcie.link.gen.current --format=csv,noheader 2>/dev/null | head -1)
GPU_PCIE_W=$(nvidia-smi --query-gpu=pcie.link.width.current --format=csv,noheader 2>/dev/null | head -1)
say "count=$GPU_COUNT names=$GPU_NAMES vram=${GPU_VRAM}MiB cc=$GPU_CC pcie=gen${GPU_PCIE_GEN}x${GPU_PCIE_W}"

PROFILE=""
if [ "$GPU_COUNT" = "2" ]; then
  case "$GPU_NAMES" in
    *"RTX 3090"*)  [ "${GPU_VRAM:-0}" -ge 24000 ] && PROFILE=PROFILE_3090_ULTRAFAST ;;
    *"RTX 5060 Ti"*) [ "${GPU_VRAM:-0}" -ge 16000 ] && PROFILE=PROFILE_5060TI_LONG_KVARN_V1 ;;
  esac
fi
if [ -z "$PROFILE" ]; then
  die "Unsupported GPU configuration. No automatic profile selected."
fi
say "PROFILE selected: $PROFILE"

# ---------------------------------------------------------------
# PHASE A4 — pre-launch verification
# ---------------------------------------------------------------
if [ "$PROFILE" = "PROFILE_3090_ULTRAFAST" ]; then
  say "PROFILE_3090_ULTRAFAST -> use syv-ai/qwen38-27b-rtx3090 single-user mode "
  say "  (CTX=fast, DFlash2 W4A16, SPEC_N=7; repo default handles 24GB single card)."
  die "Not automated here: run the syv-ai repo launcher directly on the 3090."
fi

say "=== PRE-LAUNCH CHECKS ==="
MODEL=$WORK/qwen-serving/models/Qwen3.8-27B-int4-AutoRound
DRAFT=$WORK/qwen-serving/models/Qwen3.8-27B-DFlash2-W4A16
[ -f "$MODEL/config.json" ] || die "expected model missing at $MODEL"
[ -f "$DRAFT/config.json" ] || die "DFlash2 checkpoint missing at $DRAFT"
PY=/usr/bin/python3
VER=$($PY -c "import vllm; print(vllm.__version__)" 2>/dev/null)
[ "$VER" = "0.27.1" ] || die "vLLM version mismatch: got '$VER', expected 0.27.1"
$PY -c "from vllm.v1.attention.backends.registry import AttentionBackendEnum; AttentionBackendEnum.KVARN.get_class()" 2>/dev/null \
  || die "KVarN backend not importable (run kvarn/install.sh)"
[ -f "$REPO/venv/bin/vllm" ] || { mkdir -p "$REPO/venv/bin"; ln -sf /usr/local/bin/vllm "$REPO/venv/bin/vllm"; ln -sf "$PY" "$REPO/venv/bin/python"; ln -sf "$PY" "$REPO/venv/bin/python3"; }
say "pre-launch checks OK (model, drafter, vllm $VER, KVarN backend)"

# ---------------------------------------------------------------
# Launch PROFILE_5060TI_LONG_KVARN_V1 (exact frozen command)
# ---------------------------------------------------------------
say "=== LAUNCH ==="
cd "$REPO"
export MODEL DRAFT
export SPEC=dflash2 CTX=huge PREFIX_CACHE=1 PORT=18020
export GPU_UTIL=0.90 DFLASH_MAX_LEN=262144
export CUDAGRAPH_MODE=PIECEWISE
export KV_MEM=3300000000
export VLLM_V2_CUDAGRAPH_MEM_MIB=800
export EXTRA_ARGS="--tensor-parallel-size 2"
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
bash single-user/start_qwen.sh &
SRV=$!

# ---------------------------------------------------------------
# PHASE A4 — post-launch verification (strict, no silent fallback)
# ---------------------------------------------------------------
say "=== POST-LAUNCH CHECKS (waiting for boot) ==="
BOOTED=0
for i in $(seq 1 60); do
  sleep 10
  if curl -sf -o /dev/null http://127.0.0.1:18020/health; then BOOTED=1; break; fi
  if ! kill -0 $SRV 2>/dev/null; then break; fi
done
[ "$BOOTED" = "1" ] || die "server did not become healthy (see $LOG / server.log)"

grep -q "Resolved architecture: DFlash2DraftModel" "$LOG" || die "DFlash2DraftModel NOT resolved"
grep -q '"method": "dflash"' "$LOG" || grep -q "method='dflash'" "$LOG" || die "speculative method dflash missing"
grep -q "num_speculative_tokens.: 7\|num_spec_tokens=7" "$LOG" || die "SPEC_N != 7"
grep -q "Using KVARN attention backend" "$LOG" || die "KVarN backend NOT active"
POOL=$(grep -oE "GPU KV cache size: [0-9,]+ tokens" "$LOG" | tail -1)
say "pool: $POOL"
say "bootstrap_vllm.sh: OK — PROFILE_5060TI_LONG_KVARN_V1 live on :18020"
