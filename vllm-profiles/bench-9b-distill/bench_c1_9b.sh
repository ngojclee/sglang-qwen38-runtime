#!/bin/bash
# P6: 9B 8K C1 benchmark — 3 warmup + 5 measured
set -x
MODEL_DIR="${1:-/workspace/qwen-serving/models/Qwen3.8-9B-Distill}"
SERVED="${2:-Qwen3.8-9B-Distill}"
TAG="${3:-qwen9b_native}"
PORT=18000
cd /tmp

/workspace/venv/bin/python - "$MODEL_DIR" "$SERVED" <<'PY'
import sys, json
from transformers import AutoTokenizer
tok = AutoTokenizer.from_pretrained(sys.argv[1])
sentence = ("The quick brown fox jumps over the lazy dog while the moon rises over the silent mountain. "
            "Engineers carefully measure the temperature of the GPU and adjust the cooling fans to prevent throttling. "
            "The model processes long sequences with speculative decoding and hybrid attention. ")
tokens_per = len(tok.encode(sentence))
n = 8000 // tokens_per
prompt = sentence * n
print("tokens_per_sentence", tokens_per, "n", n, "prompt_tokens", len(tok.encode(prompt)))
open('/tmp/payload_9b.json','w').write(json.dumps({
    "model": sys.argv[2],
    "messages": [{"role": "user", "content": prompt + "\n\nWrite a short answer."}],
    "max_tokens": 256,
    "stream": True,
    "temperature": 0.3,
    "chat_template_kwargs": {"enable_thinking": False},
}))
PY

run_once () {
  curl -sS -N -m 180 http://127.0.0.1:$PORT/v1/chat/completions \
    -H 'Content-Type: application/json' -d @/tmp/payload_9b.json 2>/dev/null \
    | /workspace/venv/bin/python /workspace/parse_stream.py
}

echo "=== $TAG 8K C1: 3 warmup ==="
for i in 1 2 3; do echo "warmup $i:"; run_once; done
echo "=== $TAG 8K C1: 5 measured ==="
for i in 1 2 3 4 5; do echo "run $i:"; run_once; done
echo "=== GPU ==="
nvidia-smi --query-gpu=index,utilization.gpu,memory.used,temperature.gpu,power.draw --format=csv,noheader
