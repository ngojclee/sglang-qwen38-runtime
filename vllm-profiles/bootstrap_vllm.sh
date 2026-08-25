#!/bin/bash
# ============================================================================
# bootstrap_vllm.sh — FULL from-scratch bootstrap: Qwen3.8-27B vLLM serving
# (Frozenlock INT4 W4A16 + DFlash2 W4A16, 13 syv-ai patches + KVarN)
#
# Vast template on-start:
#   bash <(curl -sL https://raw.githubusercontent.com/ngojclee/sglang-qwen38-runtime/main/vllm-profiles/bootstrap_vllm.sh)
#
# GPU detection -> strict profile select -> full setup -> launch -> verify
#   PROFILE_3090_ULTRAFAST          : 2x RTX 3090 >=24GB (27B Frozenlock BF16/FLASH_ATTN + DFlash2) — DEFAULT
#   PROFILE_QWEN38_9B_DISTILL_3090  : 2x RTX 3090 >=24GB + MODEL_VERSION=9b (9B-Distill BF16 native)
#   PROFILE_5060TI_LONG_KVARN_V1    : 2x RTX 5060 Ti >=16GB (KVarN, frozen snapshot)
#   anything else                   : STOP — no silent fallback
#
# MODEL_VERSION: 27b (default) | 9b — chọn model tải + launch (9B = empero-ai/Qwen3.8-9B-Distill)
# Log: /workspace/bootstrap_vllm.log
# ============================================================================
set -u
WORK=${WORK:-/workspace}
REPO=$WORK/qwen-serving
LOG=$WORK/bootstrap_vllm.log
exec > "$LOG" 2>&1
export DEBIAN_FRONTEND=noninteractive
export HF_XET_HIGH_PERFORMANCE=1

say() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { say "STOP: $*"; exit 1; }

# ---------------------------------------------------------------
# PHASE 1 — GPU DETECTION + PROFILE SELECT (strict)
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
MODEL_VERSION=${MODEL_VERSION:-27b}
if [ "$GPU_COUNT" = "2" ]; then
  case "$GPU_NAMES" in
    *"RTX 3090"*)
      [ "${GPU_VRAM:-0}" -ge 24000 ] && {
        if [ "$MODEL_VERSION" = "9b" ]; then PROFILE=PROFILE_QWEN38_9B_DISTILL_3090; else PROFILE=PROFILE_3090_ULTRAFAST; fi
      } ;;
    *"RTX 5060 Ti"*)  [ "${GPU_VRAM:-0}" -ge 16000 ] && PROFILE=PROFILE_5060TI_LONG_KVARN_V1 ;;
  esac
fi
[ -n "$PROFILE" ] || die "Unsupported GPU configuration. No automatic profile selected."
say "PROFILE selected: $PROFILE"

# ---------------------------------------------------------------
# PHASE 2 — SYSTEM PREP
# ---------------------------------------------------------------
say "=== System prep ==="
command -v git curl patch ninja >/dev/null 2>&1 || {
  apt-get update -y >/dev/null 2>&1
  apt-get install -y --no-install-recommends git curl patch ninja-build ca-certificates >/dev/null 2>&1
}

# Python: prefer system python3 with vllm==0.27.1 (vastai/vllm image), else venv
PY=$(command -v python3 || echo /usr/bin/python3)
if [ "$($PY -c 'import vllm; print(vllm.__version__)' 2>/dev/null)" != "0.27.1" ]; then
  say "system vllm != 0.27.1 — building venv (needs ~10GB)"
  apt-get install -y --no-install-recommends python3.12-venv python3.12-dev >/dev/null 2>&1
  python3.12 -m venv "$WORK/venv" || die "venv creation failed"
  PY=$WORK/venv/bin/python
  $PY -m pip install -U pip wheel setuptools >/dev/null 2>&1
  $PY -m pip install "vllm==0.27.1" huggingface_hub hf_transfer ninja pyarrow >/dev/null 2>&1 || die "vllm==0.27.1 install failed"
fi
VER=$($PY -c "import vllm; print(vllm.__version__)" 2>/dev/null)
[ "$VER" = "0.27.1" ] || die "vLLM version mismatch: got '$VER', expected 0.27.1"
$PY -m pip install -q pyarrow 2>/dev/null || true

# ---------------------------------------------------------------
# PHASE 2b — TUNNEL-READY (vast-tunnel pubkey, idempotent)
# ---------------------------------------------------------------
say "=== tunnel-ready: vast-tunnel pubkey ==="
mkdir -p /root/.ssh && chmod 700 /root/.ssh
TUNNEL_PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGh+qB9P1tXTnGs1gUpXRxeNH7gkDUy+7GegJUCAyCmE vast-tunnel"
touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
grep -qF "$TUNNEL_PUB" /root/.ssh/authorized_keys || printf '%s\n' "$TUNNEL_PUB" >> /root/.ssh/authorized_keys
say "authorized_keys ssh-ed25519 entries: $(grep -c '^ssh-ed25519' /root/.ssh/authorized_keys)"


# ---------------------------------------------------------------
# PHASE 3 — SYV-AI REPO + PATCHES + KVARN
# ---------------------------------------------------------------
say "=== syv-ai repo ==="
if [ -d "$REPO/.git" ]; then
  git -C "$REPO" fetch --depth 1 origin >/dev/null 2>&1 && git -C "$REPO" reset --hard origin/main >/dev/null 2>&1 || true
else
  git clone --depth 1 https://github.com/syv-ai/qwen38-27b-rtx3090 "$REPO" || die "clone syv-ai repo failed"
fi
cd "$REPO" || die "repo dir missing"

say "=== apply 13 patches ==="
SP=$($PY -c 'import vllm, os; print(os.path.dirname(vllm.__file__))' 2>/dev/null | tail -n1)
[ -n "$SP" ] || die "cannot locate vllm package"
for p in patches/*.patch; do
  patch -p1 -N -r /dev/null -d "$SP" < "$p" >/dev/null 2>&1 || say "patch note: $(basename "$p") already applied or offset"
done

say "=== KVarN install ==="
PY=$PY bash kvarn/install.sh >/dev/null 2>&1 || die "kvarn install failed"

# ---------------------------------------------------------------
# PHASE 4 — MODEL + DRAFTER DOWNLOAD
# ---------------------------------------------------------------
if [ "$PROFILE" = "PROFILE_QWEN38_9B_DISTILL_3090" ]; then
  say "=== model download (Qwen3.8-9B-Distill, ~19GB BF16) ==="
  MODEL=$REPO/models/Qwen3.8-9B-Distill
  if [ ! -f "$MODEL/config.json" ]; then
    hf download empero-ai/Qwen3.8-9B-Distill --local-dir "$MODEL" || die "9B model download failed"
  fi
else
  say "=== model download (Frozenlock, ~19GB) ==="
  MODEL=$REPO/models/Qwen3.8-27B-int4-AutoRound
  if [ ! -f "$MODEL/config.json" ]; then
    hf download Frozenlock/Qwen3.8-27B-int4-AutoRound --local-dir "$MODEL" || die "model download failed"
  fi
  say "=== DFlash2 drafter (W4A16) ==="
  DRAFT=$REPO/models/Qwen3.8-27B-DFlash2-W4A16
  if [ ! -f "$DRAFT/config.json" ]; then
    $PY prepare/fetch_dflash2.py || die "drafter fetch failed"
  fi
  say "=== draft vocab (MTP head, optional) ==="
  $PY prepare/build_draft_vocab.py "$MODEL" --ids prepare/draft_vocab_ids.json >/dev/null 2>&1 || true
fi

# launcher needs venv/bin symlinks when using system python
mkdir -p "$REPO/venv/bin"
ln -sf "$(command -v vllm || echo /usr/local/bin/vllm)" "$REPO/venv/bin/vllm" 2>/dev/null || true
ln -sf "$PY" "$REPO/venv/bin/python"
ln -sf "$PY" "$REPO/venv/bin/python3"

# ---------------------------------------------------------------
# PHASE 5 — LAUNCH per profile
# ---------------------------------------------------------------
say "=== LAUNCH [$PROFILE] ==="
if [ "$PROFILE" = "PROFILE_5060TI_LONG_KVARN_V1" ]; then
  export MODEL DRAFT
  export SPEC=dflash2 CTX=huge PREFIX_CACHE=1 PORT=18000
  export GPU_UTIL=0.90 DFLASH_MAX_LEN=262144 CUDAGRAPH_MODE=PIECEWISE
  export KV_MEM=3300000000 VLLM_V2_CUDAGRAPH_MEM_MIB=800
  export EXTRA_ARGS="--tensor-parallel-size 2 --served-model-name Qwen3.8-27B-Uncensored"
  export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
  setsid nohup bash single-user/start_qwen.sh >/dev/null 2>&1 < /dev/null &
elif [ "$PROFILE" = "PROFILE_QWEN38_9B_DISTILL_3090" ]; then
  # Research winner (J 25/08): BF16 native, no spec — xem PROFILE_QWEN38_9B_DISTILL_3090.conf
  export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
  setsid nohup "$REPO/venv/bin/vllm" serve "$MODEL" \
    --max-model-len 262144 \
    --kv-cache-dtype bfloat16 --attention-backend FLASH_ATTN \
    --tensor-parallel-size 2 --gpu-memory-utilization 0.90 \
    --max-num-batched-tokens 16384 --max-num-seqs 8 \
    --reasoning-parser qwen3 --enable-auto-tool-choice --tool-call-parser qwen3_coder \
    --served-model-name Qwen3.8-9B-Distill --host 0.0.0.0 --port 18000 \
    >/dev/null 2>&1 < /dev/null &
elif [ "$PROFILE" = "PROFILE_3090_ULTRAFAST" ]; then
  # Reference: playbook 8.3 (machine F 2x3090, BF16/FLASH_ATTN, 244 tok/s @176K)
  export VLLM_SPEC_DECODE_ATTN=1 VLLM_USE_FLASHINFER_SAMPLER=0
  export VLLM_DFLASH2_TORCH_TOPK=1 VLLM_DFLASH2_DRAFT_TOPK_TOPP=0
  setsid nohup "$REPO/venv/bin/vllm" serve "$MODEL" \
    --quantization auto_round --max-model-len 200000 \
    --kv-cache-dtype bfloat16 --attention-backend FLASH_ATTN \
    --tensor-parallel-size 2 --gpu-memory-utilization 0.90 \
    --max-num-batched-tokens 16384 --max-num-seqs 8 \
    --mamba-ssm-cache-dtype float16 --reasoning-parser qwen3 \
    --enable-auto-tool-choice --tool-call-parser qwen3_coder \
    --served-model-name Qwen3.8-27B-Uncensored --host 0.0.0.0 --port 18000 \
    --speculative-config "{\"method\":\"dflash\",\"model\":\"$DRAFT\",\"num_speculative_tokens\":7}" \
    >/dev/null 2>&1 < /dev/null &
fi
SRV=$!

# ---------------------------------------------------------------
# PHASE 6 — POST-LAUNCH VERIFY (strict, no silent fallback)
# ---------------------------------------------------------------
say "=== POST-LAUNCH CHECKS (waiting for boot) ==="
BOOTED=0
for i in $(seq 1 60); do
  sleep 10
  if curl -sf -o /dev/null http://127.0.0.1:18000/health; then BOOTED=1; break; fi
  if ! kill -0 $SRV 2>/dev/null; then break; fi
done
[ "$BOOTED" = "1" ] || die "server did not become healthy (see $LOG)"
if [ "$PROFILE" = "PROFILE_QWEN38_9B_DISTILL_3090" ]; then
  grep -q "Qwen3.8-9B-Distill" "$LOG" || die "9B-Distill served model NOT found"
else
  grep -q "Resolved architecture: DFlash2DraftModel" "$LOG" || die "DFlash2DraftModel NOT resolved"
  grep -q "num_speculative_tokens.: 7\|num_spec_tokens=7" "$LOG" || die "SPEC_N != 7"
fi
if [ "$PROFILE" = "PROFILE_5060TI_LONG_KVARN_V1" ]; then
  grep -q "Using KVARN attention backend" "$LOG" || die "KVarN backend NOT active"
fi
POOL=$(grep -oE "GPU KV cache size: [0-9,]+ tokens" "$LOG" | tail -1)
say "pool: $POOL"
say "bootstrap_vllm.sh: OK — [$PROFILE] live on :18000"
