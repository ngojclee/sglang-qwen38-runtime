#!/usr/bin/env bash
# ==============================================================================
# SGLang Qwen3.8-27B + DFlash2 Fast Provisioning Bootstrap Script (Self-Building)
# Standardized against Machine D production environment (Commit fdebc93 + Core Patches)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Parse optional arguments
AUTH_API_KEY="${SGLANG_API_KEY:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-key=*)
            AUTH_API_KEY="${1#*=}"
            shift
            ;;
        --api-key)
            AUTH_API_KEY="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "================================================================="
echo "🚀 SGLang Qwen3.8 Fast Provisioning & Self-Build Bootstrap Starting..."
echo "================================================================="

# 1. Detect Hardware
GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n 1 || echo "1")
GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -n 1 || echo "Unknown GPU")
TOTAL_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1 || echo "24576")

echo "📊 Detected Hardware: $GPU_COUNT x $GPU_NAME ($TOTAL_VRAM_MB MB VRAM per GPU)"

# 2. Compute Optimal Parameters
TP_SIZE=$GPU_COUNT
if [ "$TOTAL_VRAM_MB" -ge 22000 ]; then
    # 24GB+ GPUs (RTX 3090, 4090, A5000)
    MEM_FRACTION="0.90"
    DRAFT_TOKENS="8"
    HICACHE_RATIO="4.0"
else
    # 16GB GPUs (RTX 5060 Ti, 4080 16GB, RTX 4000)
    MEM_FRACTION="0.86"
    DRAFT_TOKENS="6"
    HICACHE_RATIO="3.0"
fi

echo "⚙️ Tuned Parameters: TP=$TP_SIZE | mem-fraction-static=$MEM_FRACTION | draft-tokens=$DRAFT_TOKENS | hicache-ratio=$HICACHE_RATIO"

# 3. Ensure Models Directory Exists
mkdir -p /root/models

# 4. Download / Link Models if not present
BASE_MODEL_PATH="/root/models/hotdogs-Qwen3.8-27B-AWQ-INT4"
DFLASH_MODEL_PATH="/root/models/Qwen3.8-27B-DFlash2"

if [ ! -d "$BASE_MODEL_PATH" ]; then
    echo "📥 Downloading Base Model: hotdog/Qwen3.8-27B-AWQ-INT4..."
    git clone https://huggingface.co/hotdog/Qwen3.8-27B-AWQ-INT4 "$BASE_MODEL_PATH" || true
fi

if [ ! -d "$DFLASH_MODEL_PATH" ]; then
    echo "📥 Downloading DFlash2 Speculative Model: z-lab/Qwen3.8-27B-DFlash2..."
    git clone https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2 "$DFLASH_MODEL_PATH" || true
fi

# 5. Build / Patch SGLang Engine for Qwen3.8 Hybrid Architecture + DFlash2
echo "🔧 Checking and Applying SGLang Qwen3.8 Hybrid Architecture Engine Patches..."
mkdir -p /sgl-workspace

if [ ! -d "/sgl-workspace/sglang" ]; then
    echo "📥 Cloning SGLang repository..."
    git clone https://github.com/sgl-project/sglang.git /sgl-workspace/sglang
    cd /sgl-workspace/sglang
    git checkout fdebc93 || true
fi

# Apply Core Patches from local repository
if [ -f "${RUNTIME_ROOT}/patches/apply_core_patches.py" ]; then
    python3 "${RUNTIME_ROOT}/patches/apply_core_patches.py" || true
fi

if [ -f "${RUNTIME_ROOT}/patches/sglang_qwen38_source_files.tar.gz" ]; then
    echo "📦 Extracting verified Qwen3.8 model executor files..."
    tar -xzf "${RUNTIME_ROOT}/patches/sglang_qwen38_source_files.tar.gz" -C /sgl-workspace/sglang/python/sglang/srt/models/ 2>/dev/null || true
fi

# Reinstall SGLang in editable mode
echo "📦 Installing SGLang in editable mode..."
pip install --no-build-isolation -e "/sgl-workspace/sglang/python[all]" flashinfer-python==0.6.14 flashinfer-cubin==0.6.14 || true

# 6. Persist Environment Variables for Vast.ai Portal & Supervisor
if [ -f /etc/environment ]; then
    sed -i '/SGLANG_MODEL/d' /etc/environment
    sed -i '/MODEL_NAME/d' /etc/environment
    echo "SGLANG_MODEL=\"$BASE_MODEL_PATH\"" >> /etc/environment
    echo "MODEL_NAME=\"$BASE_MODEL_PATH\"" >> /etc/environment
fi

# 7. Generate Tuned /etc/sglang-args.conf
AUTH_FLAG=""
if [ -n "$AUTH_API_KEY" ]; then
    AUTH_FLAG="--api-key $AUTH_API_KEY"
    echo "🔒 Configured Unified Cluster API Key protection."
fi

cat <<EOF > /etc/sglang-args.conf
--tensor-parallel-size $TP_SIZE --speculative-algorithm DFLASH --speculative-draft-model-path $DFLASH_MODEL_PATH --speculative-num-draft-tokens $DRAFT_TOKENS --speculative-draft-model-quantization unquant --kv-cache-dtype fp8_e4m3 --quantization compressed-tensors --trust-remote-code --served-model-name Qwen3.8-27B-Uncensored --reasoning-parser qwen3 --tool-call-parser qwen3_coder --enable-strict-thinking --mem-fraction-static $MEM_FRACTION --context-length 262144 --allow-auto-truncate --enable-cache-report --chunked-prefill-size 2048 --max-prefill-tokens 16384 --disable-custom-all-reduce --max-running-requests 4 --linear-attn-backend triton --enable-hierarchical-cache --hicache-ratio $HICACHE_RATIO --hicache-write-policy write_through --hicache-io-backend kernel --hicache-mem-layout page_first $AUTH_FLAG
EOF

echo "✅ Saved /etc/sglang-args.conf"

# 8. Restart SGLang Service
if command -v supervisorctl &>/dev/null; then
    echo "🔄 Restarting SGLang via supervisorctl..."
    supervisorctl restart sglang || supervisorctl start sglang
else
    echo "⚠️ Supervisor not found. Running direct launch..."
fi

# 9. Verification Loop
echo "⏳ Waiting for SGLang to initialize port 18000..."
READY=0
AUTH_HEADER=""
if [ -n "$AUTH_API_KEY" ]; then
    AUTH_HEADER="-H \"Authorization: Bearer $AUTH_API_KEY\""
fi

for i in {1..60}; do
    if eval "curl -s $AUTH_HEADER http://127.0.0.1:18000/v1/models" | grep -q "Qwen3.8-27B-Uncensored"; then
        READY=1
        echo "🎉 SGLang is UP and HEALTHY on port 18000!"
        break
    fi
    sleep 3
    echo "   ...booting ($((i*3))s)"
done

# 10. Extract Vast instance info for cluster registry
VAST_CONTAINER_ID=$(cat /root/.vast_containerlabel 2>/dev/null | tr -d 'C.' || echo "")

if [ "$READY" -eq 1 ]; then
    echo "================================================================="
    echo "✅ FAST PROVISIONING & BUILD COMPLETED SUCCESSFULLY!"
    echo "Endpoint: http://127.0.0.1:18000/v1"
    echo "Served Model: Qwen3.8-27B-Uncensored"
    if [ -n "$VAST_CONTAINER_ID" ]; then
        echo "Vast Instance ID: $VAST_CONTAINER_ID"
    fi
    echo "================================================================="
else
    echo "❌ Timeout waiting for SGLang. Check logs at /var/log/portal/sglang.log"
    exit 1
fi
