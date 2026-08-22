#!/usr/bin/env bash
# ==============================================================================
# SGLang Qwen3.8-27B + DFlash2 Fast Provisioning Bootstrap Script
# Compatible with Vast.ai SGLang templates and raw Ubuntu GPU instances
# ==============================================================================
set -euo pipefail

echo "================================================================="
echo "🚀 SGLang Qwen3.8 Fast Provisioning Bootstrap Starting..."
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

# 5. Persist Environment Variables for Vast.ai Portal & Supervisor
if [ -f /etc/environment ]; then
    sed -i '/SGLANG_MODEL/d' /etc/environment
    sed -i '/MODEL_NAME/d' /etc/environment
    echo "SGLANG_MODEL=\"$BASE_MODEL_PATH\"" >> /etc/environment
    echo "MODEL_NAME=\"$BASE_MODEL_PATH\"" >> /etc/environment
fi

# 6. Generate Tuned /etc/sglang-args.conf
cat <<EOF > /etc/sglang-args.conf
--tensor-parallel-size $TP_SIZE --speculative-algorithm DFLASH --speculative-draft-model-path $DFLASH_MODEL_PATH --speculative-num-draft-tokens $DRAFT_TOKENS --speculative-draft-model-quantization unquant --kv-cache-dtype fp8_e4m3 --quantization compressed-tensors --trust-remote-code --served-model-name Qwen3.8-27B-Uncensored --reasoning-parser qwen3 --tool-call-parser qwen3_coder --enable-strict-thinking --mem-fraction-static $MEM_FRACTION --context-length 262144 --allow-auto-truncate --enable-cache-report --chunked-prefill-size 2048 --max-prefill-tokens 16384 --disable-custom-all-reduce --max-running-requests 4 --linear-attn-backend triton --enable-hierarchical-cache --hicache-ratio $HICACHE_RATIO --hicache-write-policy write_through --hicache-io-backend kernel --hicache-mem-layout page_first
EOF

echo "✅ Saved /etc/sglang-args.conf"

# 7. Restart SGLang Service
if command -v supervisorctl &>/dev/null; then
    echo "🔄 Restarting SGLang via supervisorctl..."
    supervisorctl restart sglang || supervisorctl start sglang
else
    echo "⚠️ Supervisor not found. Running direct launch..."
fi

# 8. Verification Loop
echo "⏳ Waiting for SGLang to initialize port 18000..."
READY=0
for i in {1..60}; do
    if curl -s http://127.0.0.1:18000/v1/models | grep -q "Qwen3.8-27B-Uncensored"; then
        READY=1
        echo "🎉 SGLang is UP and HEALTHY on port 18000!"
        break
    fi
    sleep 3
    echo "   ...booting ($((i*3))s)"
done

if [ "$READY" -eq 1 ]; then
    echo "================================================================="
    echo "✅ FAST PROVISIONING COMPLETED SUCCESSFULLY!"
    echo "Endpoint: http://127.0.0.1:18000/v1"
    echo "Served Model: Qwen3.8-27B-Uncensored"
    echo "================================================================="
else
    echo "❌ Timeout waiting for SGLang. Check logs at /var/log/portal/sglang.log"
    exit 1
fi
