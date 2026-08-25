#!/bin/bash
# Launch Qwen3.8-9B-Distill BF16 native (no spec/MTP) + wait health
set -x
pkill -9 -f 'vllm.entrypoints' 2>/dev/null || true
pkill -9 -f '[v]llm.v1' 2>/dev/null || true
pkill -9 -f '[v]llm.worker' 2>/dev/null || true
sleep 6
for pid in $(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null); do kill -9 $pid 2>/dev/null || true; done
sleep 4
nohup env PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  /workspace/venv/bin/python -m vllm.entrypoints.openai.api_server \
  --model /workspace/qwen-serving/models/Qwen3.8-9B-Distill \
  --served-model-name Qwen3.8-9B-Distill \
  --max-model-len 262144 \
  --kv-cache-dtype bfloat16 \
  --attention-backend FLASH_ATTN \
  --tensor-parallel-size 2 \
  --gpu-memory-utilization 0.90 \
  --max-num-batched-tokens 16384 \
  --max-num-seqs 8 \
  --reasoning-parser qwen3 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --trust-remote-code \
  --host 127.0.0.1 --port 18000 \
  > /workspace/native_9b.log 2>&1 &
echo "LAUNCHED pid=$!"
echo "=== waiting health ==="
for i in $(seq 1 18); do
  sleep 20
  h=$(curl -sS -m 6 -o /dev/null -w '%{http_code}' http://127.0.0.1:18000/health 2>/dev/null)
  kv=$(grep -E 'GPU KV cache size|Maximum concurrency|max_model_len|Max model len' /workspace/native_9b.log 2>/dev/null | tail -3 | tr '\n' ' ')
  echo "chk $i: HEALTH=$h $kv"
  if [ "$h" = "200" ]; then echo READY; break; fi
  if grep -qE 'ValueError|RuntimeError|error:|does not support|not valid' /workspace/native_9b.log 2>/dev/null; then echo LOG_ERROR; tail -12 /workspace/native_9b.log; break; fi
done
