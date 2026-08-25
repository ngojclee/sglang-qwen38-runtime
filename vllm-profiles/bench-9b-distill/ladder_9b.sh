#!/bin/bash
# P7: 9B long-context ladder 32K..262K (stream, tách TTFT/prefill/decode) + needle
set -x
MODEL_DIR="/workspace/qwen-serving/models/Qwen3.8-9B-Distill"
SERVED="Qwen3.8-9B-Distill"
PORT=18000
OUT=/workspace/bench_9b_ladder.txt
: > "$OUT"

/workspace/venv/bin/python - "$MODEL_DIR" <<'PY'
import sys, json
from transformers import AutoTokenizer
tok = AutoTokenizer.from_pretrained(sys.argv[1])
sentence = ("The quick brown fox jumps over the lazy dog while the moon rises over the silent mountain. "
            "Engineers carefully measure the temperature of the GPU and adjust the cooling fans to prevent throttling. "
            "The model processes long sequences with speculative decoding and hybrid attention. ")
tokens_per = len(tok.encode(sentence))
print("tokens_per_sentence", tokens_per)
open('/tmp/tokens_per.txt','w').write(str(tokens_per))
PY
TP=$(cat /tmp/tokens_per.txt)

run_level () {
  local target=$1
  /workspace/venv/bin/python - "$target" "$TP" <<'PY'
import sys, json, random
from transformers import AutoTokenizer
target = int(sys.argv[1]); tp = int(sys.argv[2])
tok = AutoTokenizer.from_pretrained('/workspace/qwen-serving/models/Qwen3.8-9B-Distill')
sentence = ("The quick brown fox jumps over the lazy dog while the moon rises over the silent mountain. "
            "Engineers carefully measure the temperature of the GPU and adjust the cooling fans to prevent throttling. "
            "The model processes long sequences with speculative decoding and hybrid attention. ")
n = target // tp
parts = sentence * n
# đếm chính xác và canh sát target (≤ target+50)
toks = tok.encode(parts)
# chèn needle vào giữa
mid = len(parts)//2
prompt = parts[:mid] + " The secret code is SUNSET-CODE-7781. " + parts[mid:]
prompt_tokens = len(tok.encode(prompt))
open('/tmp/pt_last.txt','w').write(str(prompt_tokens))
open('/tmp/payload_ladder.json','w').write(json.dumps({
    "model": "Qwen3.8-9B-Distill",
    "messages": [{"role": "user", "content": prompt + "\n\nWhat is the secret code? Return the exact string."}],
    "max_tokens": 96,
    "stream": True,
    "temperature": 0.3,
    "chat_template_kwargs": {"enable_thinking": False},
}))
print("target", target, "prompt_tokens", prompt_tokens)
PY
  PT=$(grep -o 'prompt_tokens [0-9]*' <(python3 - <<'PY'
print("x")
PY
) 2>/dev/null || true)
  # parse trực tiếp từ payload creator output: in lại qua file
  curl -sS -N -m 900 http://127.0.0.1:$PORT/v1/chat/completions \
    -H 'Content-Type: application/json' -d @/tmp/payload_ladder.json 2>/dev/null \
    | /workspace/venv/bin/python /workspace/ladder_parse.py
}

echo "=== warmup 8K ==="
/workspace/venv/bin/python - 8000 "$TP" <<'PY'
import sys, json
from transformers import AutoTokenizer
target=int(sys.argv[1]); tp=int(sys.argv[2])
tok = AutoTokenizer.from_pretrained('/workspace/qwen-serving/models/Qwen3.8-9B-Distill')
sentence = ("The quick brown fox jumps over the lazy dog while the moon rises over the silent mountain. "
            "Engineers carefully measure the temperature of the GPU and adjust the cooling fans to prevent throttling. "
            "The model processes long sequences with speculative decoding and hybrid attention. ")
prompt = sentence * (target//tp)
open('/tmp/payload_warm.json','w').write(json.dumps({
    "model":"Qwen3.8-9B-Distill",
    "messages":[{"role":"user","content":prompt}],
    "max_tokens":16,"stream":True,
    "chat_template_kwargs":{"enable_thinking":False},
}))
PY
curl -sS -N -m 180 http://127.0.0.1:$PORT/v1/chat/completions -H 'Content-Type: application/json' -d @/tmp/payload_warm.json -o /dev/null 2>&1

for L in 32000 64000 128000 200000 240000 256000 262000; do
  echo "=== LEVEL $L ===" | tee -a "$OUT"
  run_level "$L" | tee -a "$OUT"
done
echo "=== DONE LADDER ==="
cat "$OUT"
